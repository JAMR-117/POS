package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"pos-backend/internal/inventory"
	"pos-backend/internal/store"
	"pos-backend/internal/sync"
)

func setupTestRouter(t *testing.T) http.Handler {
	localStore, err := store.NewStore("")
	if err != nil {
		t.Fatalf("Fallo al inicializar store de prueba: %v", err)
	}

	ctx := context.Background()
	_ = sync.SeedMigrationData(ctx, nil, localStore)

	syncService := sync.NewService(nil, localStore)
	syncHandler := sync.NewHandler(syncService)

	inventoryRepo := inventory.NewRepository(nil, localStore)
	inventoryService := inventory.NewService(inventoryRepo)
	inventoryHandler := inventory.NewHandler(inventoryService)

	r := chi.NewRouter()

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":    "UP",
			"database":  "EMBEDDED_LOCAL",
			"products":  localStore.CountProducts(),
			"timestamp": time.Now().UTC(),
		})
	})

	r.Route("/api/v1", func(r chi.Router) {
		r.Post("/sync", syncHandler.SyncBatchHandler)
		r.Get("/sync/pull", syncHandler.PullHandler)

		r.Route("/inventory", func(r chi.Router) {
			r.Get("/alerts", inventoryHandler.AlertsHandler)
			r.Get("/velocity", inventoryHandler.VelocityHandler)
		})
	})

	return r
}

func TestHealthEndpoint(t *testing.T) {
	router := setupTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Esperaba código 200 en /health, recibido: %d", rec.Code)
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Respuesta no es JSON válido: %v", err)
	}

	if resp["status"] != "UP" {
		t.Errorf("Esperaba status 'UP', recibido: %v", resp["status"])
	}
}

func TestSyncBatchEndpoint(t *testing.T) {
	router := setupTestRouter(t)

	batchPayload := map[string]any{
		"client_id": "test-pos-terminal-01",
		"timestamp": time.Now().UTC(),
		"mutations": []map[string]any{
			{
				"id":        "mut-001",
				"entity":    "sale",
				"operation": "INSERT",
				"payload": map[string]any{
					"folio": "T-1001",
					"total": 35.0,
				},
				"created_at": time.Now().UTC(),
			},
		},
	}

	bodyBytes, _ := json.Marshal(batchPayload)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK && rec.Code != http.StatusMultiStatus {
		t.Errorf("Esperaba código 200 o 207 en /api/v1/sync, recibido: %d", rec.Code)
	}
}

func TestSyncPullEndpoint(t *testing.T) {
	router := setupTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull", nil)
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Esperaba código 200 en /api/v1/sync/pull, recibido: %d", rec.Code)
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("Respuesta pull no es JSON válido: %v", err)
	}

	if _, ok := resp["products"]; !ok {
		t.Errorf("Esperaba campo 'products' en la respuesta de pull")
	}
}

func TestInventoryAlertsEndpoint(t *testing.T) {
	router := setupTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/inventory/alerts", nil)
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Esperaba código 200 en /api/v1/inventory/alerts, recibido: %d", rec.Code)
	}
}

func TestInventoryVelocityEndpoint(t *testing.T) {
	router := setupTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/inventory/velocity", nil)
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("Esperaba código 200 en /api/v1/inventory/velocity, recibido: %d", rec.Code)
	}
}
