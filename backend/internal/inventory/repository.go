package inventory

import (
	"context"
	"fmt"

	"pos-backend/internal/store"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	dbPool     *pgxpool.Pool
	localStore *store.Store
}

func NewRepository(dbPool *pgxpool.Pool, localStore *store.Store) *Repository {
	return &Repository{
		dbPool:     dbPool,
		localStore: localStore,
	}
}

// GetStockAlerts extrae productos agotados, por debajo de stock mínimo o con días restantes inferiores al umbral
func (r *Repository) GetStockAlerts(ctx context.Context, tiendaID string, maxDays float64) ([]StockAlertItem, error) {
	if r.dbPool == nil {
		if r.localStore == nil {
			return []StockAlertItem{}, nil
		}
		dtos := r.localStore.GetAlerts(maxDays)
		items := make([]StockAlertItem, len(dtos))
		for i, d := range dtos {
			items[i] = StockAlertItem{
				ID:                    d.ID,
				TiendaID:              d.TiendaID,
				CodigoBarras:          d.CodigoBarras,
				SKU:                   d.SKU,
				Descripcion:           d.Descripcion,
				StockActual:           d.StockActual,
				StockMinimo:           d.StockMinimo,
				VentasUltimos30Dias:   d.VentasUltimos30Dias,
				TotalUnidadesVendidas: d.TotalUnidadesVendidas,
				VelocidadDiaria:       d.VelocidadDiaria,
				DiasRestantes:         d.DiasRestantes,
				NivelRiesgo:           d.NivelRiesgo,
				UltimaVentaAt:         d.UltimaVentaAt,
				Ubicacion:             d.Ubicacion,
				CodigoEquivalencia:    d.CodigoEquivalencia,
			}
		}
		return items, nil
	}

	query := `
		WITH metricas AS (
			SELECT 
				id,
				tienda_id,
				codigo_barras,
				sku,
				descripcion,
				stock_actual,
				COALESCE(stock_minimo, 5.0)::NUMERIC(12, 3) AS stock_minimo,
				COALESCE(ventas_ultimos_30dias, 0.0) AS ventas_ultimos_30dias,
				COALESCE(total_unidades_vendidas, 0.0) AS total_unidades_vendidas,
				ROUND((COALESCE(ventas_ultimos_30dias, 0.0) / 30.0), 3) AS velocidad_diaria,
				CASE 
					WHEN ventas_ultimos_30dias > 0 THEN 
						ROUND((stock_actual / NULLIF(ventas_ultimos_30dias / 30.0, 0)), 1)
					ELSE 9999.0
				END AS dias_restantes,
				ultima_venta_at,
				ubicacion,
				codigo_equivalencia,
				COALESCE(es_servicio, 0) AS es_servicio
			FROM productos
			WHERE tienda_id = $1
		)
		SELECT 
			id,
			tienda_id,
			codigo_barras,
			sku,
			descripcion,
			stock_actual,
			stock_minimo,
			ventas_ultimos_30dias,
			total_unidades_vendidas,
			velocidad_diaria,
			dias_restantes,
			CASE 
				WHEN stock_actual <= 0 THEN 'CRITICO'
				WHEN dias_restantes <= ($2 / 2.0) OR stock_actual <= (stock_minimo / 2.0) THEN 'ALTO'
				ELSE 'MODERADO'
			END AS nivel_riesgo,
			ultima_venta_at,
			ubicacion,
			codigo_equivalencia
		FROM metricas
		WHERE es_servicio = 0
		  AND (stock_actual <= 0 
		       OR stock_actual <= stock_minimo 
		       OR (ventas_ultimos_30dias > 0 AND dias_restantes <= $2))
		ORDER BY 
			ventas_ultimos_30dias DESC, 
			total_unidades_vendidas DESC, 
			CASE WHEN stock_actual <= 0 THEN 0 ELSE 1 END ASC,
			stock_actual ASC;
	`

	rows, err := r.dbPool.Query(ctx, query, tiendaID, maxDays)
	if err != nil {
		return nil, fmt.Errorf("QUERY_ALERTS_FAILED: %w", err)
	}
	defer rows.Close()

	var alerts []StockAlertItem
	for rows.Next() {
		var item StockAlertItem
		err := rows.Scan(
			&item.ID,
			&item.TiendaID,
			&item.CodigoBarras,
			&item.SKU,
			&item.Descripcion,
			&item.StockActual,
			&item.StockMinimo,
			&item.VentasUltimos30Dias,
			&item.TotalUnidadesVendidas,
			&item.VelocidadDiaria,
			&item.DiasRestantes,
			&item.NivelRiesgo,
			&item.UltimaVentaAt,
			&item.Ubicacion,
			&item.CodigoEquivalencia,
		)
		if err != nil {
			return nil, fmt.Errorf("SCAN_ALERT_FAILED: %w", err)
		}
		alerts = append(alerts, item)
	}

	return alerts, nil
}

// GetCatalogVelocity lista el catálogo maestro ordenado dinámicamente por ventas y métrica de rotación
func (r *Repository) GetCatalogVelocity(ctx context.Context, tiendaID string, orderBy string, limit int, offset int) ([]VelocityItem, error) {
	if r.dbPool == nil {
		if r.localStore == nil {
			return []VelocityItem{}, nil
		}
		dtos := r.localStore.GetVelocity(orderBy, limit, offset)
		items := make([]VelocityItem, len(dtos))
		for i, d := range dtos {
			items[i] = VelocityItem{
				ID:                    d.ID,
				TiendaID:              d.TiendaID,
				CodigoBarras:          d.CodigoBarras,
				SKU:                   d.SKU,
				Descripcion:           d.Descripcion,
				Departamento:          d.Departamento,
				StockActual:           d.StockActual,
				TotalUnidadesVendidas: d.TotalUnidadesVendidas,
				VentasUltimos30Dias:   d.VentasUltimos30Dias,
				VelocidadDiaria:       d.VelocidadDiaria,
				DiasRestantes:         d.DiasRestantes,
				UltimaVentaAt:         d.UltimaVentaAt,
			}
		}
		return items, nil
	}

	sortCol := "ventas_ultimos_30dias DESC"
	switch orderBy {
	case "stock_asc":
		sortCol = "stock_actual ASC"
	case "stock_desc":
		sortCol = "stock_actual DESC"
	case "sales_asc":
		sortCol = "ventas_ultimos_30dias ASC"
	case "total_sold_desc":
		sortCol = "total_unidades_vendidas DESC"
	}

	query := fmt.Sprintf(`
		SELECT 
			id,
			tienda_id,
			codigo_barras,
			sku,
			descripcion,
			departamento,
			stock_actual,
			total_unidades_vendidas,
			ventas_ultimos_30dias,
			ROUND((ventas_ultimos_30dias / 30.0), 3) AS velocidad_diaria,
			CASE 
				WHEN ventas_ultimos_30dias > 0 THEN 
					ROUND((stock_actual / NULLIF(ventas_ultimos_30dias / 30.0, 0)), 1)
				ELSE 9999.0
			END AS dias_restantes,
			ultima_venta_at
		FROM productos
		WHERE tienda_id = $1
		ORDER BY %s
		LIMIT $2 OFFSET $3;
	`, sortCol)

	rows, err := r.dbPool.Query(ctx, query, tiendaID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("QUERY_VELOCITY_FAILED: %w", err)
	}
	defer rows.Close()

	var items []VelocityItem
	for rows.Next() {
		var item VelocityItem
		err := rows.Scan(
			&item.ID,
			&item.TiendaID,
			&item.CodigoBarras,
			&item.SKU,
			&item.Descripcion,
			&item.Departamento,
			&item.StockActual,
			&item.TotalUnidadesVendidas,
			&item.VentasUltimos30Dias,
			&item.VelocidadDiaria,
			&item.DiasRestantes,
			&item.UltimaVentaAt,
		)
		if err != nil {
			return nil, fmt.Errorf("SCAN_VELOCITY_FAILED: %w", err)
		}
		items = append(items, item)
	}

	return items, nil
}

// GetDefaultTiendaID resuelve la primera tienda activa en caso de omitir el parámetro en los requests
func (r *Repository) GetDefaultTiendaID(ctx context.Context) (string, error) {
	if r.dbPool == nil {
		return "tienda-001", nil
	}
	var id string
	err := r.dbPool.QueryRow(ctx, `SELECT id FROM tiendas WHERE activo = true LIMIT 1;`).Scan(&id)
	return id, err
}
