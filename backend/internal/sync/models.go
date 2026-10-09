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

// CancelSalePayload mapea el evento 'VENTA_CANCELADA'
type CancelSalePayload struct {
	VentaID          string    `json:"venta_id"`
	FechaCancelacion time.Time `json:"fecha_cancelacion"`
	Motivo           string    `json:"motivo"`
}

// InventoryAdjustmentPayload mapea el evento 'AJUSTE_INVENTARIO'
type InventoryAdjustmentPayload struct {
	AjusteID      string    `json:"ajuste_id"`
	ProductoID    string    `json:"producto_id"`
	StockTeorico  float64   `json:"stock_teorico"`
	StockFisico   float64   `json:"stock_fisico"`
	Diferencia    float64   `json:"diferencia"`
	Motivo        string    `json:"motivo"`
	AutorizadoPor string    `json:"autorizado_por"`
	FechaAjuste   time.Time `json:"fecha_ajuste"`
}

// CashMovementPayload mapea el evento 'MOVIMIENTO_CAJA'
type CashMovementPayload struct {
	MovimientoID string    `json:"movimiento_id"`
	CorteCajaID  string    `json:"corte_caja_id"`
	Tipo         string    `json:"tipo"`
	Monto        float64   `json:"monto"`
	Concepto     string    `json:"concepto"`
	Fecha        time.Time `json:"fecha"`
}

// ShiftTotalsDTO encapsula las métricas consolidadas del Corte Z
type ShiftTotalsDTO struct {
	MontoInicial      float64 `json:"monto_inicial"`
	VentasEfectivo    float64 `json:"ventas_efectivo"`
	VentasTarjeta     float64 `json:"ventas_tarjeta"`
	VentasOtros       float64 `json:"ventas_otros"`
	TotalVentas       float64 `json:"total_ventas"`
	TotalTickets      int     `json:"total_tickets"`
	EfectivoEsperado  float64 `json:"efectivo_esperado"`
	EfectivoDeclarado float64 `json:"efectivo_declarado"`
	Discrepancia      float64 `json:"discrepancia"`
}

// ShiftCutPayload mapea el evento 'CORTE_CAJA_REGISTRADO'
type ShiftCutPayload struct {
	CorteCajaID string         `json:"corte_caja_id"`
	TipoCorte   string         `json:"tipo_corte"`
	Totales     ShiftTotalsDTO `json:"totales"`
	FechaCierre time.Time      `json:"fecha_cierre"`
}

// CreditPaymentPayload mapea el evento 'ABONO_REGISTRADO'
type CreditPaymentPayload struct {
	AbonoID   string    `json:"abono_id"`
	ClienteID string    `json:"cliente_id"`
	Monto     float64   `json:"monto"`
	Fecha     time.Time `json:"fecha"`
}
