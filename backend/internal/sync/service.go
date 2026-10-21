package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"pos-backend/internal/store"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	dbPool     *pgxpool.Pool
	localStore *store.Store
}

func NewService(dbPool *pgxpool.Pool, localStore *store.Store) *Service {
	return &Service{
		dbPool:     dbPool,
		localStore: localStore,
	}
}

// ProcessBatch procesa de manera segura e individual cada evento del lote recibido
func (s *Service) ProcessBatch(ctx context.Context, terminalID string, req SyncBatchRequest) SyncBatchResponse {
	resp := SyncBatchResponse{
		Acks:   make([]string, 0, len(req.Events)),
		Errors: make(map[string]string),
	}

	for _, event := range req.Events {
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
	// Si no hay PostgreSQL, operar directamente sobre el almacenamiento local embebido
	if s.dbPool == nil {
		return s.processSingleEventLocal(terminalID, event)
	}

	// 1. INICIAR TRANSACCIÓN POSTGRESQL
	tx, err := s.dbPool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		// Fallback inmediato al store local si falla la transacción de PG
		if s.localStore != nil {
			return s.processSingleEventLocal(terminalID, event)
		}
		return fmt.Errorf("TX_INIT_FAILED: %w", err)
	}
	defer tx.Rollback(ctx)

	// Idempotencia en PostgreSQL
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
		return nil
	}

	// Dispatcher por tipo de evento
	switch event.EventType {
	case "PRODUCTO_CREADO", "PRODUCTO_MODIFICADO":
		if err := s.handleProductoUpsert(ctx, tx, event); err != nil {
			return err
		}
	case "PRODUCTO_ELIMINADO":
		if err := s.handleProductoEliminado(ctx, tx, event); err != nil {
			return err
		}
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
	case "ENTRADA_MERCANCIA":
		if err := s.handleEntradaMercancia(ctx, tx, terminalID, event); err != nil {
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
	case "CLIENTE_GUARDADO", "CLIENTE_CREADO", "CLIENTE_MODIFICADO":
		if err := s.handleClienteUpsert(ctx, tx, event); err != nil {
			return err
		}
	case "TURNO_ABIERTO":
		// Aceptado pasivamente
		break
	default:
		// Para no bloquear sync en eventos futuros o personalizados
		break
	}

	// Registrar idempotencia
	recordQuery := `
		INSERT INTO sync_events_processed (event_id, terminal_id, event_type, processed_at)
		VALUES ($1, $2, $3, NOW())
		ON CONFLICT DO NOTHING;
	`
	_, _ = tx.Exec(ctx, recordQuery, event.ID, terminalID, event.EventType)

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("TX_COMMIT_FAILED: %w", err)
	}

	// Reflejar también en store local como respaldo
	if s.localStore != nil {
		_ = s.processSingleEventLocal(terminalID, event)
	}

	return nil
}

// processSingleEventLocal procesa el evento en el almacenamiento local autónomo sin PostgreSQL
func (s *Service) processSingleEventLocal(terminalID string, event SyncEventDTO) error {
	if s.localStore == nil {
		return nil
	}

	// Idempotencia
	if s.localStore.IsEventProcessed(event.ID, terminalID) {
		return nil
	}

	switch event.EventType {
	case "PRODUCTO_CREADO", "PRODUCTO_MODIFICADO":
		var p store.Product
		if err := json.Unmarshal(event.Payload, &p); err == nil && p.ID != "" {
			_ = s.localStore.UpsertProduct(p)
		}
	case "PRODUCTO_ELIMINADO":
		var delPayload struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(event.Payload, &delPayload); err == nil && delPayload.ID != "" {
			_ = s.localStore.DeleteProduct(delPayload.ID)
		}
	case "VENTA_REGISTRADA":
		var payload SalePayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.VentaID != "" {
			var items []map[string]any
			_ = json.Unmarshal(event.Payload, &struct {
				Items *[]map[string]any `json:"items"`
			}{Items: &items})

			saleRec := store.SaleRecord{
				VentaID:     payload.VentaID,
				CorteCajaID: payload.CorteCajaID,
				FolioTicket: payload.FolioTicket,
				Estatus:     "completado",
				Timestamp:   payload.Timestamp,
			}
			saleRec.Totales, _ = json.Marshal(payload.Totales)
			saleRec.Pagos, _ = json.Marshal(payload.Pagos)
			saleRec.Items, _ = json.Marshal(payload.Items)

			_ = s.localStore.RecordSale(saleRec, items)
		}
	case "VENTA_CANCELADA":
		var payload CancelSalePayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.VentaID != "" {
			_ = s.localStore.CancelSale(payload.VentaID, payload.Motivo)
		}
	case "AJUSTE_INVENTARIO":
		var payload InventoryAdjustmentPayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.ProductoID != "" {
			_ = s.localStore.RecordAdjustment(payload.ProductoID, payload.StockFisico)
		}
	case "MOVIMIENTO_CAJA":
		var payload CashMovementPayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.MovimientoID != "" {
			_ = s.localStore.RecordCashMovement(store.CashMovementRecord{
				ID:          payload.MovimientoID,
				CorteCajaID: payload.CorteCajaID,
				TerminalID:  terminalID,
				Tipo:        payload.Tipo,
				Monto:       payload.Monto,
				Concepto:    payload.Concepto,
				Fecha:       payload.Fecha,
			})
		}
	case "CORTE_CAJA_REGISTRADO":
		var payload ShiftCutPayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.CorteCajaID != "" {
			totJSON, _ := json.Marshal(payload.Totales)
			_ = s.localStore.RecordShiftCut(store.ShiftCutRecord{
				ID:          payload.CorteCajaID,
				TerminalID:  terminalID,
				TipoCorte:   payload.TipoCorte,
				Totales:     totJSON,
				FechaCierre: payload.FechaCierre,
			})
		}
	case "ABONO_REGISTRADO":
		var payload CreditPaymentPayload
		if err := json.Unmarshal(event.Payload, &payload); err == nil && payload.AbonoID != "" {
			_ = s.localStore.RecordCreditPayment(store.CreditPaymentRecord{
				ID:        payload.AbonoID,
				ClienteID: payload.ClienteID,
				Monto:     payload.Monto,
				Fecha:     payload.Fecha,
			})
		}
	case "CLIENTE_CREADO", "CLIENTE_MODIFICADO":
		var clientData map[string]any
		if err := json.Unmarshal(event.Payload, &clientData); err == nil {
			if cid, ok := clientData["id"].(string); ok && cid != "" {
				_ = s.localStore.UpsertClient(cid, clientData)
			}
		}
	}

	_ = s.localStore.MarkEventProcessed(event.ID, terminalID, event.EventType)
	return nil
}

func (s *Service) handleProductoUpsert(ctx context.Context, tx pgx.Tx, event SyncEventDTO) error {
	var p store.Product
	if err := json.Unmarshal(event.Payload, &p); err != nil {
		return fmt.Errorf("MALFORMED_PRODUCT_PAYLOAD: %w", err)
	}
	if p.ID == "" {
		return errors.New("PRODUCT_ID_REQUIRED")
	}

	sql := `
		INSERT INTO productos (
			id, tienda_id, codigo_barras, sku, nombre, descripcion, marca,
			codigo_equivalencia, ubicacion, precio_compra, precio_venta,
			precio_cerrajero, precio_taller, precio_mayoreo, cantidad_mayoreo,
			stock_minimo, es_servicio, insumo_vinculado_id, cantidad_insumo,
			departamento, stock_actual, es_a_granel, updated_at
		) VALUES (
			$1, (SELECT id FROM tiendas WHERE activo = true LIMIT 1), $2, $3, $4, $5, $6,
			$7, $8, $9, $10,
			$11, $12, $13, $14,
			$15, $16, NULLIF($17, ''), $18,
			$19, $20, $21, NOW()
		)
		ON CONFLICT (id) DO UPDATE SET
			codigo_barras = EXCLUDED.codigo_barras,
			sku = EXCLUDED.sku,
			nombre = EXCLUDED.nombre,
			descripcion = EXCLUDED.descripcion,
			marca = EXCLUDED.marca,
			codigo_equivalencia = EXCLUDED.codigo_equivalencia,
			ubicacion = EXCLUDED.ubicacion,
			precio_compra = EXCLUDED.precio_compra,
			precio_venta = EXCLUDED.precio_venta,
			precio_cerrajero = EXCLUDED.precio_cerrajero,
			precio_taller = EXCLUDED.precio_taller,
			precio_mayoreo = EXCLUDED.precio_mayoreo,
			cantidad_mayoreo = EXCLUDED.cantidad_mayoreo,
			stock_minimo = EXCLUDED.stock_minimo,
			es_servicio = EXCLUDED.es_servicio,
			insumo_vinculado_id = EXCLUDED.insumo_vinculado_id,
			cantidad_insumo = EXCLUDED.cantidad_insumo,
			departamento = EXCLUDED.departamento,
			stock_actual = EXCLUDED.stock_actual,
			es_a_granel = EXCLUDED.es_a_granel,
			updated_at = NOW();
	`
	desc := p.Descripcion
	if desc == "" {
		desc = p.Nombre
	}
	nombre := p.Nombre
	if nombre == "" {
		nombre = desc
	}
	esGranel := p.EsAGranel == 1

	var insumoIDStr string
	if p.InsumoVinculadoID != nil {
		insumoIDStr = *p.InsumoVinculadoID
	}

	cantInsumo := p.CantidadInsumo
	if cantInsumo <= 0 {
		cantInsumo = 1.0
	}

	stockMin := p.StockMinimo
	if stockMin <= 0 {
		stockMin = 5.0
	}

	_, err := tx.Exec(ctx, sql,
		p.ID, p.CodigoBarras, p.SKU, nombre, desc, p.Marca,
		p.CodigoEquivalencia, p.Ubicacion, p.PrecioCompra, p.PrecioVenta,
		p.PrecioCerrajero, p.PrecioTaller, p.PrecioMayoreo, p.CantidadMayoreo,
		stockMin, p.EsServicio, insumoIDStr, cantInsumo,
		p.Departamento, p.StockActual, esGranel,
	)
	return err
}

func (s *Service) handleProductoEliminado(ctx context.Context, tx pgx.Tx, event SyncEventDTO) error {
	var payload struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return err
	}
	if payload.ID == "" {
		return nil
	}
	_, err := tx.Exec(ctx, `DELETE FROM productos WHERE id = $1;`, payload.ID)
	return err
}

func (s *Service) handleClienteUpsert(ctx context.Context, tx pgx.Tx, event SyncEventDTO) error {
	var clientMap map[string]any
	if err := json.Unmarshal(event.Payload, &clientMap); err != nil {
		return err
	}
	cid, _ := clientMap["id"].(string)
	nombre, _ := clientMap["nombre"].(string)
	if cid == "" || nombre == "" {
		return nil
	}
	tel, _ := clientMap["telefono"].(string)
	saldo, _ := clientMap["saldo_deudor"].(float64)

	sql := `
		INSERT INTO clientes (id, nombre, telefono, saldo_deudor, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (id) DO UPDATE SET
			nombre = EXCLUDED.nombre,
			telefono = EXCLUDED.telefono,
			saldo_deudor = EXCLUDED.saldo_deudor,
			updated_at = NOW();
	`
	_, err := tx.Exec(ctx, sql, cid, nombre, tel, saldo)
	return err
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

	var tiendaID string
	err = tx.QueryRow(ctx, `SELECT id FROM tiendas WHERE activo = true LIMIT 1;`).Scan(&tiendaID)
	if err != nil {
		tiendaID = "tienda-001"
	}

	insertVentaSQL := `
		INSERT INTO ventas (
			id, tienda_id, terminal_id, corte_caja_id, folio_ticket, 
			subtotal, descuento_total, impuestos_total, total, 
			pagos_desglose, fecha_venta, created_at
		) VALUES (
			$1, $2, $3, NULLIF($4, ''), $5, 
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

	for _, item := range payload.Items {
		// Garantizar que producto_id exista en PostgreSQL para evitar rechazos por FK
		ensureProductSQL := `
			INSERT INTO productos (id, tienda_id, codigo_barras, sku, nombre, descripcion, precio_venta, stock_actual, created_at, updated_at)
			VALUES ($1, $2, $1, $1, COALESCE(NULLIF($3, ''), $1), COALESCE(NULLIF($3, ''), $1), $4, 0.0, NOW(), NOW())
			ON CONFLICT (id) DO NOTHING;
		`
		var pExists bool
		_ = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM productos WHERE id = $1);`, item.ProductoID).Scan(&pExists)
		if !pExists {
			if _, err := tx.Exec(ctx, ensureProductSQL, item.ProductoID, tiendaID, item.Descripcion, item.PrecioHistorico); err != nil {
				return fmt.Errorf("ENSURE_PRODUCT_FAILED (%s): %w", item.ProductoID, err)
			}
		}

		if item.InsumoVinculadoID != nil && *item.InsumoVinculadoID != "" {
			var insExists bool
			_ = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM productos WHERE id = $1);`, *item.InsumoVinculadoID).Scan(&insExists)
			if !insExists {
				if _, err := tx.Exec(ctx, ensureProductSQL, *item.InsumoVinculadoID, tiendaID, "Insumo Vinculado", 0.0); err != nil {
					return fmt.Errorf("ENSURE_INSUMO_FAILED (%s): %w", *item.InsumoVinculadoID, err)
				}
			}
		}

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
		if _, err := tx.Exec(ctx, insertDetalleSQL,
			item.ID,
			payload.VentaID,
			item.ProductoID,
			item.Cantidad,
			item.PrecioHistorico,
			item.CostoHistorico,
			item.DescuentoLinea,
			item.TotalLinea,
		); err != nil {
			return fmt.Errorf("INSERT_DETALLE_FAILED (%s): %w", item.ID, err)
		}

		updateStockSQL := `
			UPDATE productos 
			SET stock_actual = stock_actual - $1,
			    total_unidades_vendidas = total_unidades_vendidas + $1,
			    ventas_ultimos_30dias = ventas_ultimos_30dias + $1,
			    ultima_venta_at = $2,
			    updated_at = NOW()
			WHERE id = $3;
		`
		if _, err := tx.Exec(ctx, updateStockSQL, item.Cantidad, payload.Timestamp, item.ProductoID); err != nil {
			return fmt.Errorf("UPDATE_STOCK_FAILED (%s): %w", item.ProductoID, err)
		}

		// Si es servicio con insumo vinculado, descontar también del insumo virgen
		if item.InsumoVinculadoID != nil && *item.InsumoVinculadoID != "" {
			cantInsumo := item.CantidadInsumo
			if cantInsumo <= 0 {
				cantInsumo = 1.0
			}
			descTotal := item.Cantidad * cantInsumo
			if _, err := tx.Exec(ctx, updateStockSQL, descTotal, payload.Timestamp, *item.InsumoVinculadoID); err != nil {
				return fmt.Errorf("UPDATE_INSUMO_STOCK_FAILED (%s): %w", *item.InsumoVinculadoID, err)
			}
		}
	}

	return nil
}

func (s *Service) handleVentaCancelada(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload CancelSalePayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_CANCEL_PAYLOAD: %w", err)
	}

	updateVentaSQL := `UPDATE ventas SET estatus = 'cancelado' WHERE id = $1 AND estatus = 'completado'`
	tag, err := tx.Exec(ctx, updateVentaSQL, payload.VentaID)
	if err != nil {
		return fmt.Errorf("DB_ERROR_CANCELLATION: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil
	}

	rows, err := tx.Query(ctx, `SELECT producto_id, cantidad FROM detalles_venta WHERE venta_id = $1`, payload.VentaID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	for rows.Next() {
		var prodID string
		var qty float64
		if err := rows.Scan(&prodID, &qty); err == nil {
			updateStockSQL := `
				UPDATE productos 
				SET stock_actual = stock_actual + $1,
				    total_unidades_vendidas = GREATEST(0, total_unidades_vendidas - $1),
				    ventas_ultimos_30dias = GREATEST(0, ventas_ultimos_30dias - $1),
				    updated_at = NOW()
				WHERE id = $2;
			`
			_, _ = tx.Exec(ctx, updateStockSQL, qty, prodID)
		}
	}
	return nil
}

func (s *Service) handleAjusteInventario(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload InventoryAdjustmentPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return fmt.Errorf("MALFORMED_ADJUSTMENT_PAYLOAD: %w", err)
	}

	updateSQL := `UPDATE productos SET stock_actual = $1, updated_at = NOW() WHERE id = $2`
	_, err := tx.Exec(ctx, updateSQL, payload.StockFisico, payload.ProductoID)
	return err
}

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
	return err
}

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
	return err
}

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
		return err
	}

	updateClientSQL := `UPDATE clientes SET saldo_deudor = GREATEST(0, saldo_deudor - $1) WHERE id = $2`
	_, err := tx.Exec(ctx, updateClientSQL, payload.Monto, payload.ClienteID)
	return err
}

func (s *Service) handleEntradaMercancia(ctx context.Context, tx pgx.Tx, terminalID string, event SyncEventDTO) error {
	var payload struct {
		ProductoID    string  `json:"producto_id"`
		Cantidad      float64 `json:"cantidad"`
		CostoUnitario float64 `json:"costo_unitario"`
		Motivo        string  `json:"motivo"`
		Items         []struct {
			ProductoID    string  `json:"producto_id"`
			Cantidad      float64 `json:"cantidad"`
			CostoUnitario float64 `json:"costo_unitario"`
		} `json:"items"`
	}
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return err
	}

	if len(payload.Items) > 0 {
		for _, it := range payload.Items {
			if it.ProductoID == "" || it.Cantidad <= 0 {
				continue
			}
			sql := `
				UPDATE productos 
				SET stock_actual = stock_actual + $1,
				    precio_compra = CASE WHEN $2 > 0 THEN $2 ELSE precio_compra END,
				    updated_at = NOW()
				WHERE id = $3;
			`
			_, _ = tx.Exec(ctx, sql, it.Cantidad, it.CostoUnitario, it.ProductoID)
		}
	} else if payload.ProductoID != "" && payload.Cantidad > 0 {
		sql := `
			UPDATE productos 
			SET stock_actual = stock_actual + $1,
			    precio_compra = CASE WHEN $2 > 0 THEN $2 ELSE precio_compra END,
			    updated_at = NOW()
			WHERE id = $3;
		`
		_, _ = tx.Exec(ctx, sql, payload.Cantidad, payload.CostoUnitario, payload.ProductoID)
	}

	return nil
}

// PullUpdates extrae el catálogo consolidado de productos y clientes desde PostgreSQL (o localStore)
func (s *Service) PullUpdates(ctx context.Context, tiendaID string) (*PullResponse, error) {
	resp := &PullResponse{
		Status:    "success",
		Timestamp: time.Now().UTC(),
		Products:  []ProductPullDTO{},
		Clients:   []ClientPullDTO{},
	}

	if s.dbPool == nil {
		if s.localStore == nil {
			return resp, nil
		}
		prods := s.localStore.GetAllProducts()
		for _, p := range prods {
			resp.Products = append(resp.Products, ProductPullDTO{
				ID:                    p.ID,
				CodigoBarras:          p.CodigoBarras,
				SKU:                   p.SKU,
				Nombre:                p.Nombre,
				Descripcion:           p.Descripcion,
				Marca:                 nullableStr(p.Marca),
				CodigoEquivalencia:    p.CodigoEquivalencia,
				Ubicacion:             p.Ubicacion,
				Departamento:          p.Departamento,
				PrecioCompra:          p.PrecioCompra,
				PrecioVenta:           p.PrecioVenta,
				PrecioCerrajero:       p.PrecioCerrajero,
				PrecioTaller:          p.PrecioTaller,
				PrecioMayoreo:         p.PrecioMayoreo,
				CantidadMayoreo:       p.CantidadMayoreo,
				StockActual:           p.StockActual,
				StockMinimo:           p.StockMinimo,
				EsAGranel:             p.EsAGranel,
				EsServicio:            p.EsServicio,
				VentasUltimos30Dias:   p.VentasUltimos30Dias,
				TotalUnidadesVendidas: p.TotalUnidadesVendidas,
				UltimaVentaAt:         p.UltimaVentaAt,
				UpdatedAt:             time.Now().UTC(),
			})
		}
		resp.ProductsCount = len(resp.Products)
		resp.ClientsCount = 0
		return resp, nil
	}

	// 1. Consultar productos de PostgreSQL
	prodQuery := `
		SELECT 
			id, codigo_barras, sku, nombre, descripcion, marca,
			codigo_equivalencia, ubicacion, departamento, precio_compra, precio_venta,
			precio_cerrajero, precio_taller, precio_mayoreo, cantidad_mayoreo,
			stock_actual, stock_minimo, es_a_granel, es_servicio,
			insumo_vinculado_id, cantidad_insumo,
			ventas_ultimos_30dias, total_unidades_vendidas, ultima_venta_at, updated_at
		FROM productos
		WHERE tienda_id = $1
		ORDER BY id ASC;
	`
	rows, err := s.dbPool.Query(ctx, prodQuery, tiendaID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p ProductPullDTO
			var esGranel bool
			err := rows.Scan(
				&p.ID, &p.CodigoBarras, &p.SKU, &p.Nombre, &p.Descripcion, &p.Marca,
				&p.CodigoEquivalencia, &p.Ubicacion, &p.Departamento, &p.PrecioCompra, &p.PrecioVenta,
				&p.PrecioCerrajero, &p.PrecioTaller, &p.PrecioMayoreo, &p.CantidadMayoreo,
				&p.StockActual, &p.StockMinimo, &esGranel, &p.EsServicio,
				&p.InsumoVinculadoID, &p.CantidadInsumo,
				&p.VentasUltimos30Dias, &p.TotalUnidadesVendidas, &p.UltimaVentaAt, &p.UpdatedAt,
			)
			if err == nil {
				if esGranel {
					p.EsAGranel = 1
				}
				resp.Products = append(resp.Products, p)
			}
		}
	}

	// 2. Consultar clientes de PostgreSQL
	clientQuery := `
		SELECT id, nombre, telefono, email, direccion, limite_credito, saldo_deudor, nivel_precio, updated_at
		FROM clientes
		WHERE activo = true
		ORDER BY id ASC;
	`
	cRows, err := s.dbPool.Query(ctx, clientQuery)
	if err == nil {
		defer cRows.Close()
		for cRows.Next() {
			var c ClientPullDTO
			err := cRows.Scan(
				&c.ID, &c.Nombre, &c.Telefono, &c.Email, &c.Direccion,
				&c.LimiteCredito, &c.SaldoDeudor, &c.NivelPrecio, &c.UpdatedAt,
			)
			if err == nil {
				resp.Clients = append(resp.Clients, c)
			}
		}
	}

	resp.ProductsCount = len(resp.Products)
	resp.ClientsCount = len(resp.Clients)

	return resp, nil
}
