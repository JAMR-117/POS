-- ============================================================================
-- SCRIPT DE PERSISTENCIA LOCAL (SQLITE / CLIENTE OFFLINE-FIRST)
-- Ruta: client/lib/data/local/schema.sql
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- 1. TABLA: cortes_caja
-- Manejo de turnos de operación, arqueo de caja y cierres (X y Z).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cortes_caja (
    id TEXT PRIMARY KEY NOT NULL,                       -- UUID v4 generado en cliente
    folio_corte INTEGER,                                -- Consecutivo local del turno
    usuario_id TEXT NOT NULL,                           -- Identificador del cajero
    monto_inicial REAL NOT NULL DEFAULT 0.0,            -- Fondo inicial de apertura
    monto_ventas_efectivo REAL NOT NULL DEFAULT 0.0,
    monto_ventas_tarjeta REAL NOT NULL DEFAULT 0.0,
    monto_ventas_otros REAL NOT NULL DEFAULT 0.0,       -- Transferencias, vales, etc.
    monto_retiros REAL NOT NULL DEFAULT 0.0,            -- Salidas de efectivo registradas
    tipo_corte TEXT NOT NULL CHECK (tipo_corte IN ('X', 'Z')), -- X: Parcial, Z: Cierre de turno
    discrepancia REAL DEFAULT 0.0,                      -- Diferencia declarada vs calculada
    fecha_apertura TEXT NOT NULL,                       -- ISO8601 (YYYY-MM-DDTHH:MM:SSZ)
    fecha_cierre TEXT,                                  -- NULL mientras el turno esté abierto
    estado TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado'))
);

-- ----------------------------------------------------------------------------
-- 2. TABLA: productos
-- Catálogo local para lectura inmediata en el punto de cobro.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    id TEXT PRIMARY KEY NOT NULL,                       -- UUID v4
    codigo_barras TEXT UNIQUE,                          -- EAN/UPC para escáner
    sku TEXT UNIQUE,                                    -- Código interno alternativo
    descripcion TEXT NOT NULL,
    precio_compra REAL NOT NULL DEFAULT 0.0,
    precio_venta REAL NOT NULL,
    porcentaje_impuesto REAL NOT NULL DEFAULT 0.0,      -- Ej: 0.16 para 16% IVA
    departamento TEXT DEFAULT 'General',
    stock_actual REAL NOT NULL DEFAULT 0.0,             -- Soporte decimal para granel
    es_a_granel INTEGER NOT NULL DEFAULT 0 CHECK (es_a_granel IN (0, 1)), -- 1: kg/m/lt, 0: pza
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ----------------------------------------------------------------------------
-- 3. TABLA: ventas
-- Transacciones de venta guardadas localmente de manera atómica.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ventas (
    id TEXT PRIMARY KEY NOT NULL,                       -- UUID v4 de la venta
    corte_caja_id TEXT NOT NULL,                        -- Turno activo en el que se operó
    folio_ticket TEXT,                                  -- Identificador visual de ticket
    subtotal REAL NOT NULL,
    descuento_total REAL NOT NULL DEFAULT 0.0,
    impuestos_total REAL NOT NULL DEFAULT 0.0,
    total REAL NOT NULL,
    pagos_desglose TEXT NOT NULL,                       -- JSON estructurado: [{"metodo":"efectivo","monto":100.0},{"metodo":"tarjeta","monto":50.0}]
    fecha_venta TEXT NOT NULL,                          -- ISO8601
    FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 4. TABLA: detalles_venta
-- Partidas cobradas en cada ticket con precios congelados a la fecha de emisión.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS detalles_venta (
    id TEXT PRIMARY KEY NOT NULL,                       -- UUID v4 de la línea
    venta_id TEXT NOT NULL,
    producto_id TEXT NOT NULL,
    cantidad REAL NOT NULL,                             -- Cantidad numérica (admite 0.450 para 450 gramos)
    precio_historico REAL NOT NULL,                     -- Precio unitario de venta congelado
    costo_historico REAL NOT NULL DEFAULT 0.0,          -- Costo unitario al vender (auditoría/utilidad)
    descuento_linea REAL NOT NULL DEFAULT 0.0,
    total_linea REAL NOT NULL,                          -- (cantidad * precio_historico) - descuento_linea
    FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 5. TABLA: sync_queue (Patrón Outbox)
-- Registro de eventos a despachar asíncronamente hacia el backend de Go.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_queue (
    id TEXT PRIMARY KEY NOT NULL,                       -- UUID v4 o Client-Generated ID
    event_type TEXT NOT NULL,                           -- Ej: 'VENTA_REGISTRADA', 'CORTE_CERRADO'
    payload TEXT NOT NULL,                              -- JSON textual completo de la mutación
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    error_code TEXT,                                    -- Código o mensaje retornado si falla
    created_at TEXT NOT NULL,                           -- ISO8601
    synced_at TEXT                                      -- Marca temporal al recibir ACK del server
);

-- ============================================================================
-- ÍNDICES DE RENDIMIENTO Y LATENCIA CERO
-- ============================================================================

-- Búsqueda instantánea en punto de cobro al recibir lectura de lector de códigos
CREATE INDEX IF NOT EXISTS idx_productos_codigo_barras ON productos(codigo_barras);
CREATE INDEX IF NOT EXISTS idx_productos_sku ON productos(sku);

-- Filtrado del Dispatcher/Worker de sincronización en segundo plano
CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created ON sync_queue(sync_status, created_at);

-- Consultas transaccionales y de corte por sesión
CREATE INDEX IF NOT EXISTS idx_ventas_corte_id ON ventas(corte_caja_id);
CREATE INDEX IF NOT EXISTS idx_detalles_venta_venta_id ON detalles_venta(venta_id);

-- ----------------------------------------------------------------------------
-- 7. TABLA DE USUARIOS (RBAC OFFLINE)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id TEXT PRIMARY KEY NOT NULL,
    nombre TEXT NOT NULL,
    pin_acceso TEXT NOT NULL UNIQUE,
    rol TEXT NOT NULL CHECK (rol IN ('admin', 'cajero')),
    activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1))
);

-- Usuario administrador por defecto para el primer inicio (PIN: 1234)
INSERT OR IGNORE INTO usuarios (id, nombre, pin_acceso, rol, activo) 
VALUES ('admin-001', 'Administrador Principal', '1234', 'admin', 1);

-- Usuario cajero de prueba (PIN: 5678)
INSERT OR IGNORE INTO usuarios (id, nombre, pin_acceso, rol, activo) 
VALUES ('cajero-001', 'Caja 1', '5678', 'cajero', 1);

-- ----------------------------------------------------------------------------
-- 8. TABLA DE CLIENTES Y CUENTAS POR COBRAR
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
    id TEXT PRIMARY KEY NOT NULL,
    nombre TEXT NOT NULL,
    rfc_o_dni TEXT,
    telefono TEXT,
    limite_credito REAL NOT NULL DEFAULT 0.0,
    saldo_deudor REAL NOT NULL DEFAULT 0.0,
    activo INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS abonos_credito (
    id TEXT PRIMARY KEY NOT NULL,
    cliente_id TEXT NOT NULL,
    monto REAL NOT NULL,
    fecha TEXT NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes(nombre);


ALTER TABLE ventas ADD COLUMN estatus TEXT NOT NULL DEFAULT 'completado' CHECK (estatus IN ('completado', 'cancelado'));