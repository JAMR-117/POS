package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"pos-backend/internal/inventory"
	"pos-backend/internal/printer"
	"pos-backend/internal/store"
	"pos-backend/internal/sync"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Config struct {
	Port         string
	DatabaseURL  string
	PoolMaxConns int32
	PoolMinConns int32
}

func loadConfig() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://postgres:postgres@localhost:5432/pos_db?sslmode=disable"
	}

	maxConns, _ := strconv.Atoi(os.Getenv("DB_MAX_CONNS"))
	if maxConns <= 0 {
		maxConns = 25
	}

	minConns, _ := strconv.Atoi(os.Getenv("DB_MIN_CONNS"))
	if minConns <= 0 {
		minConns = 5
	}

	return Config{
		Port:         port,
		DatabaseURL:  dbURL,
		PoolMaxConns: int32(maxConns),
		PoolMinConns: int32(minConns),
	}
}

func initDBPool(ctx context.Context, cfg Config) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("error parseando DATABASE_URL: %w", err)
	}

	poolConfig.MaxConns = cfg.PoolMaxConns
	poolConfig.MinConns = cfg.PoolMinConns
	poolConfig.MaxConnIdleTime = 5 * time.Minute
	poolConfig.MaxConnLifetime = 1 * time.Hour
	poolConfig.HealthCheckPeriod = 1 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("error instanciando pgxpool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("falla de ping con PostgreSQL: %w", err)
	}

	return pool, nil
}

// corsMiddleware asegura que cualquier petición Web (localhost, Brave, Chrome) sea admitida sin bloqueo
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
		w.Header().Set("Access-Control-Allow-Headers", "Accept, Authorization, Content-Type, X-Terminal-Id, Origin, X-Requested-With")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func main() {
	cfg := loadConfig()

	rootCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 1. Inicialización de Almacenamiento Local Embebido (Autónomo sin dependencias externas)
	dataDir := "data"
	if err := os.MkdirAll(dataDir, 0755); err != nil {
		log.Printf("[WARN] No se pudo crear directorio data: %v", err)
	}
	dataPath := filepath.Join(dataDir, "storage.json")
	localStore, err := store.NewStore(dataPath)
	if err != nil {
		log.Printf("[WARN] Error inicializando almacén local %s: %v. Inicializando almacén nuevo.", dataPath, err)
		localStore, _ = store.NewStore("")
	} else {
		log.Printf("[INFO] Almacén local embebido activo (%d productos registrados en %s)", localStore.CountProducts(), dataPath)
	}

	// 2. Conexión suave a PostgreSQL (Fallback automático si no está corriendo)
	var dbPool *pgxpool.Pool
	dbPool, err = initDBPool(rootCtx, cfg)
	if err != nil {
		log.Printf("[WARN] PostgreSQL no disponible (%v). Operando en MODO AUTÓNOMO LOCAL con almacenamiento JSON embebido.", err)
		dbPool = nil
	} else {
		defer dbPool.Close()
		log.Println("[INFO] Conexión a PostgreSQL establecida con éxito.")
	}

	// 3. Inicialización de Capas de Negocio
	syncService := sync.NewService(dbPool, localStore)
	syncHandler := sync.NewHandler(syncService)

	// Auto-siembra de catálogo y clientes migrados desde el segundo 1
	_ = sync.SeedMigrationData(rootCtx, dbPool, localStore)

	inventoryRepo := inventory.NewRepository(dbPool, localStore)
	inventoryService := inventory.NewService(inventoryRepo)
	inventoryHandler := inventory.NewHandler(inventoryService)

	printerHandler := printer.NewHandler()

	// 4. Router Chi y Middlewares
	r := chi.NewRouter()

	r.Use(corsMiddleware)
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(25 * time.Second))

	// Endpoint Healthcheck
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		status := "UP"
		dbStatus := "EMBEDDED_LOCAL"
		if dbPool != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := dbPool.Ping(ctx); err == nil {
				dbStatus = "POSTGRESQL"
			} else {
				dbStatus = "POSTGRESQL_DEGRADED"
				status = "DEGRADED"
			}
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":    status,
			"database":  dbStatus,
			"products":  localStore.CountProducts(),
			"timestamp": time.Now().UTC(),
		})
	})

	// Endpoints API v1
	r.Route("/api/v1", func(r chi.Router) {
		// Receptor de cola de mutaciones Offline-First y Descarga Bidireccional
		r.Post("/sync", syncHandler.SyncBatchHandler)
		r.Get("/sync/pull", syncHandler.PullHandler)

		// Rutas BI de Inventario y Analítica
		r.Route("/inventory", func(r chi.Router) {
			r.Get("/alerts", inventoryHandler.AlertsHandler)
			r.Get("/velocity", inventoryHandler.VelocityHandler)
		})

		// Rutas de Impresión Térmica Física (Puente Local / Network)
		r.Get("/printers", printerHandler.GetPrinters)
		r.Post("/print", printerHandler.Print)
	})

	// 5. Servidor HTTP y Apagado Controlado
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 25 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("[INFO] Servidor POS backend escuchando en http://127.0.0.1:%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()

	select {
	case err := <-serverErrors:
		log.Fatalf("[FATAL] Fallo del servidor HTTP: %v", err)
	case <-rootCtx.Done():
		log.Println("[INFO] Recibida señal de terminación. Cerrando conexiones...")

		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := srv.Shutdown(shutdownCtx); err != nil {
			srv.Close()
			log.Fatalf("[ERROR] Apagado forzado del servidor: %v", err)
		}

		log.Println("[INFO] Servidor detenido de manera limpia.")
	}
}
