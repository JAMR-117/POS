package inventory

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	dbPool *pgxpool.Pool
}

func NewRepository(dbPool *pgxpool.Pool) *Repository {
	return &Repository{dbPool: dbPool}
}

// GetStockAlerts extrae productos agotados, por debajo de stock mínimo o con días restantes inferiores al umbral
func (r *Repository) GetStockAlerts(ctx context.Context, tiendaID string, maxDays float64) ([]StockAlertItem, error) {
	// stock_minimo por defecto = 5.0 si la columna no existe o es nula; velocity = ventas_ultimos_30dias / 30.0
	query := `
		WITH metricas AS (
			SELECT 
				id,
				tienda_id,
				codigo_barras,
				sku,
				descripcion,
				stock_actual,
				5.0::NUMERIC(12, 3) AS stock_minimo,
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
			velocidad_diaria,
			dias_restantes,
			CASE 
				WHEN stock_actual <= 0 THEN 'CRITICO'
				WHEN dias_restantes <= ($2 / 2.0) OR stock_actual <= (stock_minimo / 2.0) THEN 'ALTO'
				ELSE 'MODERADO'
			END AS nivel_riesgo,
			ultima_venta_at
		FROM metricas
		WHERE stock_actual <= stock_minimo 
		   OR (ventas_ultimos_30dias > 0 AND dias_restantes <= $2)
		ORDER BY ventas_ultimos_30dias DESC, stock_actual ASC;
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
			&item.VelocidadDiaria,
			&item.DiasRestantes,
			&item.NivelRiesgo,
			&item.UltimaVentaAt,
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
	var id string
	err := r.dbPool.QueryRow(ctx, `SELECT id FROM tiendas WHERE activo = true LIMIT 1;`).Scan(&id)
	return id, err
}
