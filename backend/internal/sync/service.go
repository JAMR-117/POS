package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	dbPool *pgxpool.Pool
}

func NewService(dbPool *pgxpool.Pool) *Service {
	return &Service{dbPool: dbPool}
}

// ProcessBatch procesa de manera segura e individual cada evento del lote recibido
func (s *Service) ProcessBatch(ctx context.Context, terminalID string, req SyncBatchRequest) SyncBatchResponse {
	resp := SyncBatchResponse{
		Acks:   make([]string, 0, len(req.Events)),
		Errors: make(map[string]string),
	}

	for _, event := range req.Events {
		// Timeout estricto de 5 segundos por evento individual para no retener conexiones del pool
		eventCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err := s.processSingleEvent(eventCtx, terminalID, event)
		cancel()

		if err != nil {
			resp.Errors[event.ID] = err.Error()
		} else {
			resp.Acks = append(resp.Acks, event.ID)
		}
	}

	return resp
}

func (s *Service) processSingleEvent(ctx context.Context, terminalID string, event SyncEventDTO) error {
	// Iniciar transacción con nivel de aislamiento estándar Read Committed
	tx, err := s.dbPool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("TX_INIT_FAILED: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. COMPROBACIÓN DE IDEMPOTENCIA
	// Si (event_id, terminal_id) ya fue procesado, no se repite ninguna mutación contable
	var exists bool
	checkQuery := `
		SELECT EXISTS (
			SELECT 1 FROM sync_events_processed 
			WHERE event_id = $1 AND terminal_id = $2
		);
	`
	if err := tx.QueryRow(ctx, checkQuery, event.ID, terminalID).Scan(&exists); err != nil {
		return fmt.Errorf("IDEMPOTENCY_CHECK_FAILED: %w", err)
	}

	if exists {
		// Ya aplicado previamente: confirmar inmediatamente (ACK)
		return nil
	}

	// 2. DISPATCHER POR TIPO DE EVENTO
	// 2. DISPATCHER POR TIPO DE EVENTO (Dentro de processSingleEvent)
	switch event.EventType {
	case "VENTA_REGISTRADA":
		if err := s.handleVentaRegistrada(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "VENTA_CANCELADA":
		if err := s.handleVentaCancelada(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "AJUSTE_INVENTARIO":
		if err := s.handleAjusteInventario(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "MOVIMIENTO_CAJA":
		if err := s.handleMovimientoCaja(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "CORTE_CAJA_REGISTRADO":
		if err := s.handleCorteCajaRegistrado(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "ABONO_REGISTRADO":
		if err := s.handleAbonoRegistrado(ctx, tx, terminalID, event); err != nil {
			return err
		}
	case "TURNO_ABIERTO":
		// Ignorado pasivamente (Opcional si guardas el evento de apertura aislado,
		// pero la consolidación real la hacemos en CORTE_CAJA_REGISTRADO).
		return nil
	default:
		return fmt.Errorf("UNSUPPORTED_EVENT_TYPE: %s", event.EventType)
	}

	// 3. REGISTRO EN LA TABLA DE IDEMPOTENCIA
	recordQuery := `
		INSERT INTO sync_events_processed (event_id, terminal_id, event_type, processed_at)
		VALUES ($1, $2, $3, NOW());
	`
	if _, err := tx.Exec(ctx, recordQuery, event.ID, terminalID, event.EventType); err != nil {
		return fmt.Errorf("IDEMPOTENCY_RECORD_FAILED: %w", err)
	}

	// 4. COMMIT DE LA MUTACIÓN
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("TX_COMMIT_FAILED: %w", err)
	}

	return nil
}

func (s *Service) handleVentaRegistrada(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload SalePayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_SALE_PAYLOAD: %w", err)
	}

	if payload.VentaID == "" {
		return errors.New("INVALID_SALE: venta_id no puede ser nulo")
	}

	if len(payload.Items) == 0 {
		return errors.New("INVALID_SALE: venta sin partidas")
	}

	pagosJSON, err := json.Marshal(payload.Pagos)
	if err != nil {
		return fmt.Errorf("PAYMENT_SERIALIZATION_FAILED: %w", err)
	}

	// Identificar tienda_id vinculada a la terminal/corte
	// Como fallback inicial toma la primera tienda disponible
	var tiendaID string
	err = tx.QueryRow(ctx, `SELECT id FROM tiendas WHERE activo = true LIMIT 1;`).Scan(&tiendaID)
	if err != nil {
		return fmt.Errorf("NO_ACTIVE_TIENDA_FOUND: %w", err)
	}

	// 1. Inserción central en la tabla ventas
	insertVentaSQL := `
		INSERT INTO ventas (
			id, tienda_id, terminal_id, corte_caja_id, folio_ticket, 
			subtotal, descuento_total, impuestos_total, total, 
			pagos_desglose, fecha_venta, created_at
		) VALUES (
			$1, $2, $3, NULLIF($4, '')::uuid, $5, 
			$6, $7, $8, $9, 
			$10, $11, NOW()
		)
		ON CONFLICT (id) DO NOTHING;
	`
	_, err = tx.Exec(ctx, insertVentaSQL,
		payload.VentaID,
		tiendaID,
		terminalID,
		payload.CorteCajaID,
		payload.FolioTicket,
		payload.Totales.Subtotal,
		payload.Totales.Descuentos,
		payload.Totales.Impuestos,
		payload.Totales.Total,
		pagosJSON,
		payload.Timestamp,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) {
			return fmt.Errorf("DB_ERROR_VENTA [%s]: %s", pgErr.Code, pgErr.Message)
		}
		return fmt.Errorf("INSERT_VENTA_FAILED: %w", err)
	}

	// 2. Inserción de partidas y actualización atómica del inventario
	for _, item := range payload.Items {
		insertDetalleSQL := `
			INSERT INTO detalles_venta (
				id, venta_id, producto_id, cantidad, 
				precio_historico, costo_historico, descuento_linea, total_linea
			) VALUES (
				$1, $2, $3, $4, 
				$5, $6, $7, $8
			)
			ON CONFLICT (id) DO NOTHING;
		`
		_, err = tx.Exec(ctx, insertDetalleSQL,
			item.ID,
			payload.VentaID,
			item.ProductoID,
			item.Cantidad,
			item.PrecioHistorico,
			item.CostoHistorico,
			item.DescuentoLinea,
			item.TotalLinea,
		)
		if err != nil {
			return fmt.Errorf("INSERT_DETALLE_FAILED for item %s: %w", item.ID, err)
		}

		// Descuento de stock y acumulación de métricas para la Fase 5 (BI)
		updateStockSQL := `
			UPDATE productos 
			SET stock_actual = stock_actual - $1,
			    total_unidades_vendidas = total_unidades_vendidas + $1,
			    ventas_ultimos_30dias = ventas_ultimos_30dias + $1,
			    ultima_venta_at = $2,
			    updated_at = NOW()
			WHERE id = $3;
		`
		tag, err := tx.Exec(ctx, updateStockSQL, item.Cantidad, payload.Timestamp, item.ProductoID)
		if err != nil {
			return fmt.Errorf("UPDATE_STOCK_FAILED for product %s: %w", item.ProductoID, err)
		}

		if tag.RowsAffected() == 0 {
			return fmt.Errorf("PRODUCT_NOT_FOUND: no se encontró el producto %s para descontar stock", item.ProductoID)
		}
	}

	return nil
}

// handleVentaCancelada busca la venta, la invalida y retorna el stock de sus partidas a la matriz.
func (s *Service) handleVentaCancelada(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload CancelSalePayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_CANCEL_PAYLOAD: %w", err)
	}

	// 1. Marcar venta como cancelada
	updateVentaSQL := `UPDATE ventas SET estatus = 'cancelado' WHERE id = $1 AND estatus = 'completado'`
	tag, err := tx.Exec(ctx, updateVentaSQL, payload.VentaID)
	if err != nil {
		return fmt.Errorf("DB_ERROR_CANCELLATION: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("SALE_NOT_FOUND_OR_ALREADY_CANCELLED: %s", payload.VentaID)
	}

	// 2. Recuperar partidas originales para reintegro de inventario
	rows, err := tx.Query(ctx, `SELECT producto_id, cantidad FROM detalles_venta WHERE venta_id = $1`, payload.VentaID)
	if err != nil {
		return fmt.Errorf("QUERY_DETAILS_FAILED: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var prodID string
		var qty float64
		if err := rows.Scan(&prodID, &qty); err != nil {
			return fmt.Errorf("SCAN_DETAILS_FAILED: %w", err)
		}

		// 3. Reintegro atómico de stock (Revierte las métricas BI y el stock físico)
		updateStockSQL := `
			UPDATE productos 
			SET stock_actual = stock_actual + $1,
			    total_unidades_vendidas = total_unidades_vendidas - $1,
			    ventas_ultimos_30dias = GREATEST(0, ventas_ultimos_30dias - $1),
			    updated_at = NOW()
			WHERE id = $2;
		`
		if _, err := tx.Exec(ctx, updateStockSQL, qty, prodID); err != nil {
			return fmt.Errorf("RESTORE_STOCK_FAILED for %s: %w", prodID, err)
		}
	}
	return nil
}

// handleAjusteInventario corrige mermas o robos estableciendo el stock a la realidad física.
func (s *Service) handleAjusteInventario(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload InventoryAdjustmentPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_ADJUSTMENT_PAYLOAD: %w", err)
	}

	// Ajusta usando el stock físico reportado por el frontend para absorber cualquier deltas
	updateSQL := `UPDATE productos SET stock_actual = $1, updated_at = NOW() WHERE id = $2`
	if _, err := tx.Exec(ctx, updateSQL, payload.StockFisico, payload.ProductoID); err != nil {
		return fmt.Errorf("UPDATE_ADJUSTMENT_FAILED: %w", err)
	}
	return nil
}

// handleMovimientoCaja inserta entradas y salidas de efectivo (gastos) en PostgreSQL.
func (s *Service) handleMovimientoCaja(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload CashMovementPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_CASH_MOVEMENT_PAYLOAD: %w", err)
	}

	insertSQL := `
		INSERT INTO movimientos_caja (id, corte_caja_id, terminal_id, tipo, monto, concepto, fecha, created_at) 
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		ON CONFLICT (id) DO NOTHING;
	`
	_, err := tx.Exec(ctx, insertSQL, payload.MovimientoID, payload.CorteCajaID, terminalID, payload.Tipo, payload.Monto, payload.Concepto, payload.Fecha)
	if err != nil {
		return fmt.Errorf("INSERT_CASH_MOVEMENT_FAILED: %w", err)
	}
	return nil
}

// handleCorteCajaRegistrado consolida las métricas del Corte Z en la tabla central cortes_caja.
func (s *Service) handleCorteCajaRegistrado(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload ShiftCutPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_SHIFT_CUT_PAYLOAD: %w", err)
	}

	upsertSQL := `
		INSERT INTO cortes_caja (
			id, terminal_id, tipo_corte, monto_inicial, ventas_efectivo, 
			ventas_tarjeta, ventas_otros, total_ventas, total_tickets, 
			efectivo_esperado, efectivo_declarado, discrepancia, fecha_cierre, created_at
		) VALUES (
			$1, $2, $3, $4, $5, 
			$6, $7, $8, $9,
			$10, $11, $12, $13, NOW()
		)
		ON CONFLICT (id) DO UPDATE SET
			tipo_corte = EXCLUDED.tipo_corte,
			ventas_efectivo = EXCLUDED.ventas_efectivo,
			ventas_tarjeta = EXCLUDED.ventas_tarjeta,
			ventas_otros = EXCLUDED.ventas_otros,
			total_ventas = EXCLUDED.total_ventas,
			total_tickets = EXCLUDED.total_tickets,
			efectivo_esperado = EXCLUDED.efectivo_esperado,
			efectivo_declarado = EXCLUDED.efectivo_declarado,
			discrepancia = EXCLUDED.discrepancia,
			fecha_cierre = EXCLUDED.fecha_cierre,
			updated_at = NOW();
	`
	_, err := tx.Exec(ctx, upsertSQL,
		payload.CorteCajaID, terminalID, payload.TipoCorte, payload.Totales.MontoInicial,
		payload.Totales.VentasEfectivo, payload.Totales.VentasTarjeta, payload.Totales.VentasOtros,
		payload.Totales.TotalVentas, payload.Totales.TotalTickets, payload.Totales.EfectivoEsperado,
		payload.Totales.EfectivoDeclarado, payload.Totales.Discrepancia, payload.FechaCierre,
	)
	if err != nil {
		return fmt.Errorf("UPSERT_SHIFT_CUT_FAILED: %w", err)
	}
	return nil
}

// handleAbonoRegistrado asimila pagos de crédito y reajusta saldos deudores de clientes.
func (s *Service) handleAbonoRegistrado(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload CreditPaymentPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_CREDIT_PAYMENT_PAYLOAD: %w", err)
	}

	insertSQL := `
		INSERT INTO abonos_credito (id, cliente_id, terminal_id, monto, fecha, created_at) 
		VALUES ($1, $2, $3, $4, $5, NOW())
		ON CONFLICT (id) DO NOTHING;
	`
	if _, err := tx.Exec(ctx, insertSQL, payload.AbonoID, payload.ClienteID, terminalID, payload.Monto, payload.Fecha); err != nil {
		return fmt.Errorf("INSERT_ABONO_FAILED: %w", err)
	}

	updateClientSQL := `UPDATE clientes SET saldo_deudor = GREATEST(0, saldo_deudor - $1) WHERE id = $2`
	if _, err := tx.Exec(ctx, updateClientSQL, payload.Monto, payload.ClienteID); err != nil {
		return fmt.Errorf("UPDATE_CLIENT_DEBT_FAILED: %w", err)
	}
	return nil
}
