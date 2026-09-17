package inventory

import (
	"time"
)

// StockAlertItem representa la proyección predictiva de quiebre de stock
type StockAlertItem struct {
	ID                  string     `json:"id"`
	TiendaID            string     `json:"tienda_id"`
	CodigoBarras        *string    `json:"codigo_barras"`
	SKU                 *string    `json:"sku"`
	Descripcion         string     `json:"descripcion"`
	StockActual         float64    `json:"stock_actual"`
	StockMinimo         float64    `json:"stock_minimo"`
	VentasUltimos30Dias float64    `json:"ventas_ultimos_30dias"`
	VelocidadDiaria     float64    `json:"velocidad_diaria"`
	DiasRestantes       float64    `json:"dias_restantes"`
	NivelRiesgo         string     `json:"nivel_riesgo"` // CRITICO, ALTO, MODERADO
	UltimaVentaAt       *time.Time `json:"ultima_venta_at"`
}

// VelocityItem consolida el catálogo para ordenamiento por rotación comercial
type VelocityItem struct {
	ID                    string     `json:"id"`
	TiendaID              string     `json:"tienda_id"`
	CodigoBarras          *string    `json:"codigo_barras"`
	SKU                   *string    `json:"sku"`
	Descripcion           string     `json:"descripcion"`
	Departamento          string     `json:"departamento"`
	StockActual           float64    `json:"stock_actual"`
	TotalUnidadesVendidas float64    `json:"total_unidades_vendidas"`
	VentasUltimos30Dias   float64    `json:"ventas_ultimos_30dias"`
	VelocidadDiaria       float64    `json:"velocidad_diaria"`
	DiasRestantes         float64    `json:"dias_restantes"`
	UltimaVentaAt         *time.Time `json:"ultima_venta_at"`
}
