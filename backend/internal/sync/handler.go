package sync

import (
	"encoding/json"
	"net/http"
)

type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// SyncBatchHandler procesa las peticiones enviadas por el SyncApiClient
func (h *Handler) SyncBatchHandler(w http.ResponseWriter, r *http.Request) {
	terminalID := r.Header.Get("X-Terminal-Id")
	if terminalID == "" {
		terminalID = "terminal-default-001"
	}

	// Límite defensivo para payloads de entrada (10 MB máx)
	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)

	var req SyncBatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error": "BAD_REQUEST: Payload JSON inválido o excede el tamaño máximo permitido",
		})
		return
	}

	if len(req.Events) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(SyncBatchResponse{
			Acks:   []string{},
			Errors: map[string]string{},
		})
		return
	}

	// Ejecutar procesamiento con el contexto derivado de la petición
	resp := h.service.ProcessBatch(r.Context(), terminalID, req)

	w.Header().Set("Content-Type", "application/json")
	// Si hubo fallos parciales devuelve Multi-Status (207), de lo contrario 200 OK
	if len(resp.Errors) > 0 && len(resp.Acks) > 0 {
		w.WriteHeader(http.StatusMultiStatus)
	} else {
		w.WriteHeader(http.StatusOK)
	}

	_ = json.NewEncoder(w).Encode(resp)
}
