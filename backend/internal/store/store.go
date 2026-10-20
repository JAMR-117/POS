package store

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Product estructura un registro de catálogo compatible con todas las columnas de cerrajería
type Product struct {
	ID                    string     `json:"id"`
	CodigoBarras          *string    `json:"codigo_barras,omitempty"`
	SKU                   *string    `json:"sku,omitempty"`
	Nombre                string     `json:"nombre"`
	Descripcion           string     `json:"descripcion"`
	Marca                 string     `json:"marca"`
	CodigoEquivalencia    *string    `json:"codigo_equivalencia,omitempty"`
	Ubicacion             *string    `json:"ubicacion,omitempty"`
	PrecioCompra          float64    `json:"precio_compra"`
	PrecioVenta           float64    `json:"precio_venta"`
	PrecioCerrajero       *float64   `json:"precio_cerrajero,omitempty"`
	PrecioTaller          *float64   `json:"precio_taller,omitempty"`
	PorcentajeImpuesto    float64    `json:"porcentaje_impuesto"`
	Departamento          string     `json:"departamento"`
	StockActual           float64    `json:"stock_actual"`
	StockMinimo           float64    `json:"stock_minimo"`
	EsAGranel             int        `json:"es_a_granel"`
	CantidadMayoreo       *float64   `json:"cantidad_mayoreo,omitempty"`
	PrecioMayoreo         *float64   `json:"precio_mayoreo,omitempty"`
	EsServicio            int        `json:"es_servicio"`
	InsumoVinculadoID     *string    `json:"insumo_vinculado_id,omitempty"`
	CantidadInsumo        float64    `json:"cantidad_insumo"`
	TotalUnidadesVendidas float64    `json:"total_unidades_vendidas"`
	VentasUltimos30Dias   float64    `json:"ventas_ultimos_30dias"`
	UltimaVentaAt         *time.Time `json:"ultima_venta_at,omitempty"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

// SaleRecord representa una venta consolidada
type SaleRecord struct {
	VentaID     string          `json:"venta_id"`
	CorteCajaID string          `json:"corte_caja_id"`
	FolioTicket *string         `json:"folio_ticket,omitempty"`
	Totales     json.RawMessage `json:"totales"`
	Pagos       json.RawMessage `json:"pagos"`
	Items       json.RawMessage `json:"items"`
	Estatus     string          `json:"estatus"` // "completado", "cancelado"
	Timestamp   time.Time       `json:"timestamp"`
}

// CashMovementRecord almacena entradas y salidas de efectivo
type CashMovementRecord struct {
	ID          string    `json:"id"`
	CorteCajaID string    `json:"corte_caja_id"`
	TerminalID  string    `json:"terminal_id"`
	Tipo        string    `json:"tipo"`
	Monto       float64   `json:"monto"`
	Concepto    string    `json:"concepto"`
	Fecha       time.Time `json:"fecha"`
}

// ShiftCutRecord consolida el Corte X o Z
type ShiftCutRecord struct {
	ID          string          `json:"id"`
	TerminalID  string          `json:"terminal_id"`
	TipoCorte   string          `json:"tipo_corte"`
	Totales     json.RawMessage `json:"totales"`
	FechaCierre time.Time       `json:"fecha_cierre"`
}

// CreditPaymentRecord registra abonos a créditos
type CreditPaymentRecord struct {
	ID        string    `json:"id"`
	ClienteID string    `json:"cliente_id"`
	Monto     float64   `json:"monto"`
	Fecha     time.Time `json:"fecha"`
}

// ProcessedEvent registra idempotencia de eventos recibidos
type ProcessedEvent struct {
	EventID     string    `json:"event_id"`
	TerminalID  string    `json:"terminal_id"`
	EventType   string    `json:"event_type"`
	ProcessedAt time.Time `json:"processed_at"`
}

// StoreData es el contenedor serializable completo
type StoreData struct {
	Products        map[string]Product             `json:"products"`
	ProcessedEvents map[string]ProcessedEvent      `json:"processed_events"`
	Sales           map[string]SaleRecord          `json:"sales"`
	CashMovements   []CashMovementRecord           `json:"cash_movements"`
	ShiftCuts       map[string]ShiftCutRecord      `json:"shift_cuts"`
	CreditPayments  []CreditPaymentRecord          `json:"credit_payments"`
	Clients         map[string]map[string]any      `json:"clients"`
}

// Store provee almacenamiento concurrente persistente sin PostgreSQL
type Store struct {
	mu       sync.RWMutex
	filePath string
	data     StoreData
}

// NewStore inicializa o carga la base de datos embebida
func NewStore(filePath string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(filePath), 0755); err != nil {
		return nil, err
	}

	s := &Store{
		filePath: filePath,
		data: StoreData{
			Products:        make(map[string]Product),
			ProcessedEvents: make(map[string]ProcessedEvent),
			Sales:           make(map[string]SaleRecord),
			CashMovements:   make([]CashMovementRecord, 0),
			ShiftCuts:       make(map[string]ShiftCutRecord),
			CreditPayments:  make([]CreditPaymentRecord, 0),
			Clients:         make(map[string]map[string]any),
		},
	}

	if err := s.load(); err != nil {
		// Si el archivo no existe aún, guardar estructura vacía inicial
		if os.IsNotExist(err) {
			_ = s.save()
		} else {
			return nil, err
		}
	}

	return s, nil
}

func (s *Store) load() error {
	bytes, err := os.ReadFile(s.filePath)
	if err != nil {
		return err
	}
	var data StoreData
	if err := json.Unmarshal(bytes, &data); err != nil {
		return err
	}
	if data.Products == nil {
		data.Products = make(map[string]Product)
	}
	if data.ProcessedEvents == nil {
		data.ProcessedEvents = make(map[string]ProcessedEvent)
	}
	if data.Sales == nil {
		data.Sales = make(map[string]SaleRecord)
	}
	if data.ShiftCuts == nil {
		data.ShiftCuts = make(map[string]ShiftCutRecord)
	}
	if data.Clients == nil {
		data.Clients = make(map[string]map[string]any)
	}
	s.data = data
	return nil
}

func (s *Store) save() error {
	bytes, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.filePath, bytes, 0644)
}

// IsEventProcessed verifica idempotencia
func (s *Store) IsEventProcessed(eventID, terminalID string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	key := eventID + "_" + terminalID
	_, exists := s.data.ProcessedEvents[key]
	return exists
}

// MarkEventProcessed registra el evento como procesado
func (s *Store) MarkEventProcessed(eventID, terminalID, eventType string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	key := eventID + "_" + terminalID
	s.data.ProcessedEvents[key] = ProcessedEvent{
		EventID:     eventID,
		TerminalID:  terminalID,
		EventType:   eventType,
		ProcessedAt: time.Now().UTC(),
	}
	return s.save()
}

// UpsertProduct inserta o actualiza un producto con todas las columnas de cerrajería
func (s *Store) UpsertProduct(p Product) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	existing, ok := s.data.Products[p.ID]
	if ok {
		// Mantener métricas históricas calculadas previamente
		p.TotalUnidadesVendidas = existing.TotalUnidadesVendidas
		p.VentasUltimos30Dias = existing.VentasUltimos30Dias
		p.UltimaVentaAt = existing.UltimaVentaAt
		if p.CreatedAt.IsZero() {
			p.CreatedAt = existing.CreatedAt
		}
	} else if p.CreatedAt.IsZero() {
		p.CreatedAt = time.Now().UTC()
	}
	p.UpdatedAt = time.Now().UTC()

	s.data.Products[p.ID] = p
	return s.save()
}

// DeleteProduct elimina un producto del catálogo local
func (s *Store) DeleteProduct(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.data.Products, id)
	return s.save()
}

// RecordSale asimila una venta y descuenta stock atómicamente
func (s *Store) RecordSale(sale SaleRecord, items []map[string]any) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.data.Sales[sale.VentaID] = sale

	now := time.Now().UTC()
	for _, it := range items {
		prodID, _ := it["producto_id"].(string)
		if prodID == "" || prodID == "ART-COMUN" {
			continue
		}
		var qty float64
		switch v := it["cantidad"].(type) {
		case float64:
			qty = v
		case int:
			qty = float64(v)
		}

		if p, ok := s.data.Products[prodID]; ok {
			p.StockActual -= qty
			p.TotalUnidadesVendidas += qty
			p.VentasUltimos30Dias += qty
			p.UltimaVentaAt = &now
			p.UpdatedAt = now
			s.data.Products[prodID] = p
		}
	}

	return s.save()
}

// CancelSale anula una venta y reincorpora el stock
func (s *Store) CancelSale(ventaID, motivo string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	sale, ok := s.data.Sales[ventaID]
	if !ok || sale.Estatus == "cancelado" {
		return nil
	}

	sale.Estatus = "cancelado"
	s.data.Sales[ventaID] = sale

	// Devolver stock si los items fueron registrados
	var items []map[string]any
	if err := json.Unmarshal(sale.Items, &items); err == nil {
		for _, it := range items {
			prodID, _ := it["producto_id"].(string)
			if prodID == "" || prodID == "ART-COMUN" {
				continue
			}
			var qty float64
			switch v := it["cantidad"].(type) {
			case float64:
				qty = v
			case int:
				qty = float64(v)
			}

			if p, ok := s.data.Products[prodID]; ok {
				p.StockActual += qty
				p.TotalUnidadesVendidas = math.Max(0, p.TotalUnidadesVendidas-qty)
				p.VentasUltimos30Dias = math.Max(0, p.VentasUltimos30Dias-qty)
				p.UpdatedAt = time.Now().UTC()
				s.data.Products[prodID] = p
			}
		}
	}

	return s.save()
}

// RecordAdjustment actualiza el stock físico reportado
func (s *Store) RecordAdjustment(productoID string, stockFisico float64) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if p, ok := s.data.Products[productoID]; ok {
		p.StockActual = stockFisico
		p.UpdatedAt = time.Now().UTC()
		s.data.Products[productoID] = p
	}
	return s.save()
}

// RecordCashMovement almacena entrada/salida de dinero
func (s *Store) RecordCashMovement(m CashMovementRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.CashMovements = append(s.data.CashMovements, m)
	return s.save()
}

// RecordShiftCut almacena el corte de caja
func (s *Store) RecordShiftCut(cut ShiftCutRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.ShiftCuts[cut.ID] = cut
	return s.save()
}

// RecordCreditPayment registra un abono
func (s *Store) RecordCreditPayment(pay CreditPaymentRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.CreditPayments = append(s.data.CreditPayments, pay)
	return s.save()
}

// UpsertClient actualiza datos o saldos de clientes
func (s *Store) UpsertClient(clienteID string, payload map[string]any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.data.Clients[clienteID] = payload
	return s.save()
}

// StockAlertDTO mapea la respuesta esperada por /api/v1/inventory/alerts
type StockAlertDTO struct {
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
	NivelRiesgo         string     `json:"nivel_riesgo"`
	UltimaVentaAt       *time.Time `json:"ultima_venta_at"`
}

// GetAlerts genera el listado de alertas predictivas de escasez
func (s *Store) GetAlerts(runwayDays float64) []StockAlertDTO {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var alerts []StockAlertDTO
	for _, p := range s.data.Products {
		if p.EsServicio == 1 {
			continue
		}

		velDiaria := math.Round((p.VentasUltimos30Dias/30.0)*1000) / 1000
		diasRestantes := 9999.0
		if velDiaria > 0 {
			diasRestantes = math.Round((p.StockActual/velDiaria)*10) / 10
		}

		stockMin := p.StockMinimo
		if stockMin <= 0 {
			stockMin = 5.0
		}

		var riesgo string
		if p.StockActual <= 0 {
			riesgo = "CRITICO"
		} else if diasRestantes <= (runwayDays/2.0) || p.StockActual <= (stockMin/2.0) {
			riesgo = "ALTO"
		} else {
			riesgo = "MODERADO"
		}

		// Filtrar solo productos en riesgo
		if p.StockActual <= stockMin || (p.VentasUltimos30Dias > 0 && diasRestantes <= runwayDays) {
			desc := p.Descripcion
			if desc == "" {
				desc = p.Nombre
			}
			alerts = append(alerts, StockAlertDTO{
				ID:                  p.ID,
				TiendaID:            "tienda-001",
				CodigoBarras:        p.CodigoBarras,
				SKU:                 p.SKU,
				Descripcion:         desc,
				StockActual:         p.StockActual,
				StockMinimo:         stockMin,
				VentasUltimos30Dias: p.VentasUltimos30Dias,
				VelocidadDiaria:     velDiaria,
				DiasRestantes:       diasRestantes,
				NivelRiesgo:         riesgo,
				UltimaVentaAt:       p.UltimaVentaAt,
			})
		}
	}

	sort.Slice(alerts, func(i, j int) bool {
		return alerts[i].StockActual < alerts[j].StockActual
	})

	return alerts
}

// VelocityItemDTO mapea la respuesta de /api/v1/inventory/velocity
type VelocityItemDTO struct {
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

// GetVelocity retorna el catálogo ordenado por ventas y rotación
func (s *Store) GetVelocity(sortBy string, limit, offset int) []VelocityItemDTO {
	s.mu.RLock()
	defer s.mu.RUnlock()

	items := make([]VelocityItemDTO, 0, len(s.data.Products))
	for _, p := range s.data.Products {
		velDiaria := math.Round((p.VentasUltimos30Dias/30.0)*1000) / 1000
		diasRestantes := 9999.0
		if velDiaria > 0 {
			diasRestantes = math.Round((p.StockActual/velDiaria)*10) / 10
		}

		desc := p.Descripcion
		if desc == "" {
			desc = p.Nombre
		}

		items = append(items, VelocityItemDTO{
			ID:                    p.ID,
			TiendaID:              "tienda-001",
			CodigoBarras:          p.CodigoBarras,
			SKU:                   p.SKU,
			Descripcion:           desc,
			Departamento:          p.Departamento,
			StockActual:           p.StockActual,
			TotalUnidadesVendidas: p.TotalUnidadesVendidas,
			VentasUltimos30Dias:   p.VentasUltimos30Dias,
			VelocidadDiaria:       velDiaria,
			DiasRestantes:         diasRestantes,
			UltimaVentaAt:         p.UltimaVentaAt,
		})
	}

	// Ordenamiento según parámetro sort
	sort.Slice(items, func(i, j int) bool {
		switch sortBy {
		case "stock_asc":
			return items[i].StockActual < items[j].StockActual
		case "runway_asc":
			return items[i].DiasRestantes < items[j].DiasRestantes
		case "sales_desc":
			fallthrough
		default:
			return items[i].VentasUltimos30Dias > items[j].VentasUltimos30Dias
		}
	})

	if offset >= len(items) {
		return []VelocityItemDTO{}
	}
	end := offset + limit
	if end > len(items) {
		end = len(items)
	}
	return items[offset:end]
}

// CountProducts retorna el número total de productos almacenados
func (s *Store) CountProducts() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.data.Products)
}
