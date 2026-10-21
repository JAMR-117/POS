package sync

import (
	"context"
	"encoding/csv"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"pos-backend/internal/store"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SeedMigrationData carga automáticamente catalogo_migrado_pos.csv y clientes_migrados_pos.csv en PostgreSQL y localStore
func SeedMigrationData(ctx context.Context, dbPool *pgxpool.Pool, localStore *store.Store) error {
	log.Println("[SEEDER] Verificando e importando catálogo y clientes migrados...")

	catalogPath := findFile("catalogo_migrado_pos.csv")
	clientsPath := findFile("clientes_migrados_pos.csv")

	if catalogPath != "" {
		if err := seedCatalog(ctx, dbPool, localStore, catalogPath); err != nil {
			log.Printf("[SEEDER] Advertencia al sembrar catálogo: %v", err)
		}
	} else {
		log.Println("[SEEDER] Archivo catalogo_migrado_pos.csv no encontrado para auto-siembra.")
	}

	if clientsPath != "" {
		if err := seedClients(ctx, dbPool, clientsPath); err != nil {
			log.Printf("[SEEDER] Advertencia al sembrar clientes: %v", err)
		}
	} else {
		log.Println("[SEEDER] Archivo clientes_migrados_pos.csv no encontrado para auto-siembra.")
	}

	return nil
}

func findFile(name string) string {
	candidates := []string{
		filepath.Join("C:", "POS", "migracion", name),
		filepath.Join("..", "migracion", name),
		filepath.Join("migracion", name),
		filepath.Join("..", "client", "assets", name),
	}
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func seedCatalog(ctx context.Context, dbPool *pgxpool.Pool, localStore *store.Store, path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	reader.LazyQuotes = true
	reader.FieldsPerRecord = -1

	headers, err := reader.Read()
	if err != nil {
		return err
	}

	colMap := make(map[string]int)
	for i, h := range headers {
		colMap[strings.ToLower(strings.TrimSpace(h))] = i
	}

	tiendaID := "8377312b-9a2a-4d0f-b74d-f2e0ca6c4d2a"
	var tiendaExiste bool
	if dbPool != nil {
		_ = dbPool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM tiendas WHERE id = $1);`, tiendaID).Scan(&tiendaExiste)
		if !tiendaExiste {
			_, _ = dbPool.Exec(ctx, `
				INSERT INTO tiendas (id, clave, nombre, activo) 
				VALUES ($1, 'SUC-001', 'Tienda Principal', true) 
				ON CONFLICT (clave) DO NOTHING;
			`, tiendaID)
		}
	}

	upsertProductSQL := `
		INSERT INTO productos (
			id, tienda_id, codigo_barras, sku, nombre, descripcion, marca,
			codigo_equivalencia, ubicacion, departamento, precio_compra, precio_venta,
			precio_cerrajero, precio_taller, precio_mayoreo, cantidad_mayoreo,
			stock_actual, stock_minimo, es_a_granel, es_servicio,
			ventas_ultimos_30dias, total_unidades_vendidas, ultima_venta_at,
			created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7,
			$8, $9, $10, $11, $12,
			$13, $14, $15, $16,
			$17, $18, $19, $20,
			$21, $22, $23,
			NOW(), NOW()
		)
		ON CONFLICT (id) DO UPDATE SET
			nombre = EXCLUDED.nombre,
			descripcion = EXCLUDED.descripcion,
			marca = EXCLUDED.marca,
			codigo_equivalencia = EXCLUDED.codigo_equivalencia,
			ubicacion = EXCLUDED.ubicacion,
			departamento = EXCLUDED.departamento,
			precio_compra = EXCLUDED.precio_compra,
			precio_venta = EXCLUDED.precio_venta,
			precio_cerrajero = EXCLUDED.precio_cerrajero,
			precio_taller = EXCLUDED.precio_taller,
			precio_mayoreo = EXCLUDED.precio_mayoreo,
			cantidad_mayoreo = EXCLUDED.cantidad_mayoreo,
			stock_minimo = EXCLUDED.stock_minimo,
			ventas_ultimos_30dias = GREATEST(productos.ventas_ultimos_30dias, EXCLUDED.ventas_ultimos_30dias),
			total_unidades_vendidas = GREATEST(productos.total_unidades_vendidas, EXCLUDED.total_unidades_vendidas),
			ultima_venta_at = COALESCE(EXCLUDED.ultima_venta_at, productos.ultima_venta_at),
			updated_at = NOW();
	`

	var tx pgx.Tx
	if dbPool != nil {
		var errTx error
		tx, errTx = dbPool.Begin(ctx)
		if errTx == nil {
			defer tx.Rollback(ctx)
		}
	}

	var localProds []store.Product
	count := 0
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) == 0 {
			continue
		}

		getVal := func(col string) string {
			if idx, ok := colMap[col]; ok && idx < len(record) {
				return strings.TrimSpace(record[idx])
			}
			return ""
		}

		codigo := getVal("codigo")
		sku := getVal("sku")
		if codigo == "" && sku == "" {
			continue
		}
		id := codigo
		if id == "" {
			id = sku
		}

		nombre := getVal("nombre")
		desc := getVal("descripcion")
		if nombre == "" {
			nombre = desc
		}
		if desc == "" {
			desc = nombre
		}

		marca := getVal("marca")
		molde := getVal("codigo_equivalencia")
		ubi := getVal("ubicacion")
		depto := getVal("departamento")
		if depto == "" {
			depto = "General"
		}

		pCompra, _ := strconv.ParseFloat(getVal("precio_compra"), 64)
		pVenta, _ := strconv.ParseFloat(getVal("precio_venta"), 64)
		pCerrajero, _ := strconv.ParseFloat(getVal("precio_cerrajero"), 64)
		pTaller, _ := strconv.ParseFloat(getVal("precio_taller"), 64)
		pMayoreo, _ := strconv.ParseFloat(getVal("precio_mayoreo"), 64)
		cantMayoreo, _ := strconv.ParseFloat(getVal("cantidad_mayoreo"), 64)
		stockActual, _ := strconv.ParseFloat(getVal("stock_actual"), 64)
		stockMin, _ := strconv.ParseFloat(getVal("stock_minimo"), 64)
		if stockMin <= 0 {
			stockMin = 5.0
		}
		granelInt, _ := strconv.Atoi(getVal("es_a_granel"))
		esGranel := granelInt == 1
		servInt, _ := strconv.Atoi(getVal("es_servicio"))

		v30d, _ := strconv.ParseFloat(getVal("ventas_ultimos_30dias"), 64)
		totVendidas, _ := strconv.ParseFloat(getVal("total_unidades_vendidas"), 64)
		ultVentaStr := getVal("ultima_venta_at")

		var ultVenta *time.Time
		if ultVentaStr != "" {
			for _, layout := range []string{"2006-01-02 15:04:05", time.RFC3339} {
				if t, err := time.Parse(layout, ultVentaStr); err == nil {
					ultVenta = &t
					break
				}
			}
		}

		if tx != nil {
			_, err = tx.Exec(ctx, upsertProductSQL,
				id, tiendaID, codigo, sku, nombre, desc, marca,
				nullableStr(molde), nullableStr(ubi), depto, pCompra, pVenta,
				nullableFloat(pCerrajero), nullableFloat(pTaller), nullableFloat(pMayoreo), nullableFloat(cantMayoreo),
				stockActual, stockMin, esGranel, servInt,
				v30d, totVendidas, ultVenta,
			)
			if err != nil {
				continue
			}
		} else if dbPool != nil {
			_, err = dbPool.Exec(ctx, upsertProductSQL,
				id, tiendaID, codigo, sku, nombre, desc, marca,
				nullableStr(molde), nullableStr(ubi), depto, pCompra, pVenta,
				nullableFloat(pCerrajero), nullableFloat(pTaller), nullableFloat(pMayoreo), nullableFloat(cantMayoreo),
				stockActual, stockMin, esGranel, servInt,
				v30d, totVendidas, ultVenta,
			)
			if err != nil {
				continue
			}
		}

		if localStore != nil {
			localProds = append(localProds, store.Product{
				ID:                    id,
				CodigoBarras:          &codigo,
				SKU:                   &sku,
				Nombre:                nombre,
				Descripcion:           desc,
				Marca:                 marca,
				CodigoEquivalencia:    nullableStr(molde),
				Ubicacion:             nullableStr(ubi),
				Departamento:          depto,
				PrecioCompra:          pCompra,
				PrecioVenta:           pVenta,
				PrecioCerrajero:       nullableFloat(pCerrajero),
				PrecioTaller:          nullableFloat(pTaller),
				PrecioMayoreo:         nullableFloat(pMayoreo),
				CantidadMayoreo:       nullableFloat(cantMayoreo),
				StockActual:           stockActual,
				StockMinimo:           stockMin,
				EsAGranel:             granelInt,
				EsServicio:            servInt,
				VentasUltimos30Dias:   v30d,
				TotalUnidadesVendidas: totVendidas,
				UltimaVentaAt:         ultVenta,
			})
		}

		count++
	}

	if tx != nil {
		if err := tx.Commit(ctx); err != nil {
			log.Printf("[SEEDER] Error al confirmar transacción de productos: %v", err)
		}
	}

	if localStore != nil && len(localProds) > 0 {
		_ = localStore.UpsertProductsBatch(localProds)
	}

	log.Printf("[SEEDER] %d productos sembrados/actualizados correctamente en PostgreSQL.", count)
	return nil
}

func seedClients(ctx context.Context, dbPool *pgxpool.Pool, path string) error {
	if dbPool == nil {
		return nil
	}

	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	reader := csv.NewReader(f)
	reader.LazyQuotes = true
	reader.FieldsPerRecord = -1

	headers, err := reader.Read()
	if err != nil {
		return err
	}

	colMap := make(map[string]int)
	for i, h := range headers {
		colMap[strings.ToLower(strings.TrimSpace(h))] = i
	}

	upsertClientSQL := `
		INSERT INTO clientes (
			id, nombre, telefono, email, direccion, limite_credito, saldo_deudor,
			created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, NOW(), NOW()
		)
		ON CONFLICT (id) DO UPDATE SET
			nombre = EXCLUDED.nombre,
			telefono = EXCLUDED.telefono,
			direccion = EXCLUDED.direccion,
			limite_credito = EXCLUDED.limite_credito,
			saldo_deudor = EXCLUDED.saldo_deudor,
			updated_at = NOW();
	`

	var tx pgx.Tx
	var errTx error
	tx, errTx = dbPool.Begin(ctx)
	if errTx == nil {
		defer tx.Rollback(ctx)
	}

	count := 0
	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil || len(record) == 0 {
			continue
		}

		getVal := func(col string) string {
			if idx, ok := colMap[col]; ok && idx < len(record) {
				return strings.TrimSpace(record[idx])
			}
			return ""
		}

		id := getVal("id")
		nombre := getVal("nombre")
		if id == "" || nombre == "" {
			continue
		}

		tel := getVal("telefono")
		email := getVal("email")
		dir := getVal("direccion")
		limite, _ := strconv.ParseFloat(getVal("limite_credito"), 64)
		saldo, _ := strconv.ParseFloat(getVal("saldo_actual"), 64)

		if tx != nil {
			_, err = tx.Exec(ctx, upsertClientSQL,
				id, nombre, nullableStr(tel), nullableStr(email), nullableStr(dir),
				limite, saldo,
			)
			if err != nil {
				continue
			}
		} else {
			_, err = dbPool.Exec(ctx, upsertClientSQL,
				id, nombre, nullableStr(tel), nullableStr(email), nullableStr(dir),
				limite, saldo,
			)
			if err != nil {
				continue
			}
		}

		count++
	}

	if tx != nil {
		if err := tx.Commit(ctx); err != nil {
			log.Printf("[SEEDER] Error al confirmar clientes: %v", err)
		}
	}

	log.Printf("[SEEDER] %d clientes sembrados/actualizados correctamente en PostgreSQL.", count)
	return nil
}

func nullableStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func nullableFloat(f float64) *float64 {
	if f <= 0 {
		return nil
	}
	return &f
}
