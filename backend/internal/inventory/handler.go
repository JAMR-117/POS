package inventory

import (
	"encoding/json"
	"net/http"
	"strconv"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// AlertsHandler maneja GET /api/v1/inventory/alerts?runway_days=7&tienda_id=UUID
func (h *Handler) AlertsHandler(w http.ResponseWriter, r *http.Request) {
	tiendaID := r.URL.Query().Get("tienda_id")

	runwayDays := 7.0
	if rawDays := r.URL.Query().Get("runway_days"); rawDays != "" {
		if parsed, err := strconv.ParseFloat(rawDays, 64); err == nil && parsed > 0 {
			runwayDays = parsed
		}
	}

	alerts, err := h.service.GetAlerts(r.Context(), tiendaID, runwayDays)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"threshold_days": runwayDays,
		"count":          len(alerts),
		"alerts":         alerts,
	})
}

// VelocityHandler maneja GET /api/v1/inventory/velocity?sort=sales_desc&limit=50&offset=0
func (h *Handler) VelocityHandler(w http.ResponseWriter, r *http.Request) {
	tiendaID := r.URL.Query().Get("tienda_id")
	sortBy := r.URL.Query().Get("sort")

	limit := 50
	if rawLimit := r.URL.Query().Get("limit"); rawLimit != "" {
		if parsed, err := strconv.Atoi(rawLimit); err == nil {
			limit = parsed
		}
	}

	offset := 0
	if rawOffset := r.URL.Query().Get("offset"); rawOffset != "" {
		if parsed, err := strconv.Atoi(rawOffset); err == nil {
			offset = parsed
		}
	}

	catalog, err := h.service.GetVelocityCatalog(r.Context(), tiendaID, sortBy, limit, offset)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"limit":  limit,
		"offset": offset,
		"count":  len(catalog),
		"items":  catalog,
	})
}
