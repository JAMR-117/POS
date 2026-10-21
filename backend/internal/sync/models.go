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
	ID                string  `json:"id"`
	ProductoID        string  `json:"producto_id"`
	Nombre            string  `json:"nombre,omitempty"`
	Descripcion       string  `json:"descripcion"`
	Cantidad          float64 `json:"cantidad"` // Soporte decimal para venta a granel
	PrecioHistorico   float64 `json:"precio_historico"`
	CostoHistorico    float64 `json:"costo_historico"`
	DescuentoLinea    float64 `json:"descuento_linea"`
	TotalLinea        float64 `json:"total_linea"`
	EsServicio        int     `json:"es_servicio,omitempty"`
	InsumoVinculadoID *string `json:"insumo_vinculado_id,omitempty"`
	CantidadInsumo    float64 `json:"cantidad_insumo,omitempty"`
	EtiquetaPrecio    string  `json:"etiqueta_precio,omitempty"`
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

// PullResponse estructura la respuesta del endpoint GET /api/v1/sync/pull
type PullResponse struct {
	Status        string           `json:"status"`
	Timestamp     time.Time        `json:"timestamp"`
	ProductsCount int              `json:"products_count"`
	ClientsCount  int              `json:"clients_count"`
	Products      []ProductPullDTO `json:"products"`
	Clients       []ClientPullDTO  `json:"clients"`
}

type ProductPullDTO struct {
	ID                    string     `json:"id"`
	CodigoBarras          *string    `json:"codigo_barras"`
	SKU                   *string    `json:"sku"`
	Nombre                string     `json:"nombre"`
	Descripcion           string     `json:"descripcion"`
	Marca                 *string    `json:"marca"`
	CodigoEquivalencia    *string    `json:"codigo_equivalencia"`
	Ubicacion             *string    `json:"ubicacion"`
	Departamento          string     `json:"departamento"`
	PrecioCompra          float64    `json:"precio_compra"`
	PrecioVenta           float64    `json:"precio_venta"`
	PrecioCerrajero       *float64   `json:"precio_cerrajero"`
	PrecioTaller          *float64   `json:"precio_taller"`
	PrecioMayoreo         *float64   `json:"precio_mayoreo"`
	CantidadMayoreo       *float64   `json:"cantidad_mayoreo"`
	StockActual           float64    `json:"stock_actual"`
	StockMinimo           float64    `json:"stock_minimo"`
	EsAGranel             int        `json:"es_a_granel"`
	EsServicio            int        `json:"es_servicio"`
	InsumoVinculadoID     *string    `json:"insumo_vinculado_id"`
	CantidadInsumo        float64    `json:"cantidad_insumo"`
	VentasUltimos30Dias   float64    `json:"ventas_ultimos_30dias"`
	TotalUnidadesVendidas float64    `json:"total_unidades_vendidas"`
	UltimaVentaAt         *time.Time `json:"ultima_venta_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

type ClientPullDTO struct {
	ID            string    `json:"id"`
	Nombre        string    `json:"nombre"`
	Telefono      *string   `json:"telefono"`
	Email         *string   `json:"email"`
	Direccion     *string   `json:"direccion"`
	LimiteCredito float64   `json:"limite_credito"`
	SaldoDeudor   float64   `json:"saldo_deudor"`
	NivelPrecio   string    `json:"nivel_precio"`
	UpdatedAt     time.Time `json:"updated_at"`
}
