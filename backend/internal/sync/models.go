package sync

import (
	"encoding/json"
	"time"
)

// SyncBatchRequest estructura el payload emitido por el cliente Flutter (SyncApiClient)
type SyncBatchRequest struct {
	BatchSize int            `json:"batch_size"`
	SentAt    time.Time      `json:"sent_at"`
	Events    []SyncEventDTO `json:"events"`
}

// SyncEventDTO representa cada entrada deserializada de sync_queue
type SyncEventDTO struct {
	ID         string          `json:"id"`
	EventType  string          `json:"event_type"`
	Payload    json.RawMessage `json:"payload"`
	RetryCount int             `json:"retry_count"`
	CreatedAt  time.Time       `json:"created_at"`
}

// PaymentBreakdownDTO mapea los cobros combinados (efectivo, tarjeta, transferencia)
type PaymentBreakdownDTO struct {
	Metodo string  `json:"metodo"`
	Monto  float64 `json:"monto"`
}

// SaleTotalsDTO desglosa los valores monetarios de la transacción
type SaleTotalsDTO struct {
	Subtotal   float64 `json:"subtotal"`
	Descuentos float64 `json:"descuentos"`
	Impuestos  float64 `json:"impuestos"`
	Total      float64 `json:"total"`
}

// SaleItemDTO mapea cada artículo vendido en el ticket
type SaleItemDTO struct {
	ID              string  `json:"id"`
	ProductoID      string  `json:"producto_id"`
	Descripcion     string  `json:"descripcion"`
	Cantidad        float64 `json:"cantidad"` // Soporte decimal para venta a granel
	PrecioHistorico float64 `json:"precio_historico"`
	CostoHistorico  float64 `json:"costo_historico"`
	DescuentoLinea  float64 `json:"descuento_linea"`
	TotalLinea      float64 `json:"total_linea"`
}

// SalePayload representa el payload decodificado de eventos 'VENTA_REGISTRADA'
type SalePayload struct {
	VentaID     string                `json:"venta_id"`
	CorteCajaID string                `json:"corte_caja_id"`
	FolioTicket *string               `json:"folio_ticket"`
	Totales     SaleTotalsDTO         `json:"totales"`
	Pagos       []PaymentBreakdownDTO `json:"pagos"`
	Items       []SaleItemDTO         `json:"items"`
	Timestamp   time.Time             `json:"timestamp"`
}

// SyncBatchResponse define el contrato de respuesta JSON consumido por el SyncApiClient
type SyncBatchResponse struct {
	Acks   []string          `json:"acks"`
	Errors map[string]string `json:"errors"`
}
