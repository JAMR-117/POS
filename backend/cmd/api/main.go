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
	"strconv"
	"syscall"
	"time"

	"pos-backend/internal/inventory"
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

	pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		return nil, fmt.Errorf("falla de ping con PostgreSQL: %w", err)
	}

	return pool, nil
}

func main() {
	cfg := loadConfig()

	rootCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// 1. Conexión al pool de PostgreSQL
	dbPool, err := initDBPool(rootCtx, cfg)
	if err != nil {
		log.Fatalf("[FATAL] Error conectando a base de datos: %v", err)
	}
	defer dbPool.Close()
	log.Println("[INFO] Conexión a PostgreSQL lista.")

	// 2. Inicialización de Capas de Negocio
	// Sincronización (Fase 4)
	syncService := sync.NewService(dbPool)
	syncHandler := sync.NewHandler(syncService)

	// BI e Inventario Predictivo (Fase 5)
	inventoryRepo := inventory.NewRepository(dbPool)
	inventoryService := inventory.NewService(inventoryRepo)
	inventoryHandler := inventory.NewHandler(inventoryService)

	// 3. Router Chi y Middlewares
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(20 * time.Second))

	// Healthcheck
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		status := "UP"
		dbStatus := "OK"
		if err := dbPool.Ping(ctx); err != nil {
			status = "DEGRADED"
			dbStatus = "UNREACHABLE"
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":    status,
			"database":  dbStatus,
			"timestamp": time.Now().UTC(),
		})
	})

	// Endpoints API v1
	r.Route("/api/v1", func(r chi.Router) {
		// Receptor de cola de mutaciones Offline-First
		r.Post("/sync", syncHandler.SyncBatchHandler)

		// Rutas BI de Inventario y Analítica
		r.Route("/inventory", func(r chi.Router) {
			r.Get("/alerts", inventoryHandler.AlertsHandler)
			r.Get("/velocity", inventoryHandler.VelocityHandler)
		})
	})

	// 4. Servidor HTTP y Apagado Controlado
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 25 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("[INFO] Servidor POS backend escuchando en :%s", cfg.Port)
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
