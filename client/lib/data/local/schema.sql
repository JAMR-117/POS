-- ============================================================================
-- SCRIPT DE PERSISTENCIA LOCAL (SQLITE / CLIENTE OFFLINE-FIRST)
-- Especializado para Cerrajería, Duplicado, Proveeduría y Electrónica Automotriz
-- Ruta: client/lib/data/local/schema.sql
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- 1. TABLA: cortes_caja
-- Manejo de turnos de operación, arqueo de caja y cierres (X y Z).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cortes_caja (
    id TEXT PRIMARY KEY NOT NULL,
    folio_corte INTEGER,
    usuario_id TEXT NOT NULL,
    monto_inicial REAL NOT NULL DEFAULT 0.0,
    monto_ventas_efectivo REAL NOT NULL DEFAULT 0.0,
    monto_ventas_tarjeta REAL NOT NULL DEFAULT 0.0,
    monto_ventas_otros REAL NOT NULL DEFAULT 0.0,
    monto_retiros REAL NOT NULL DEFAULT 0.0,
    tipo_corte TEXT NOT NULL CHECK (tipo_corte IN ('X', 'Z')),
    discrepancia REAL DEFAULT 0.0,
    fecha_apertura TEXT NOT NULL,
    fecha_cierre TEXT,
    estado TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado'))
);

-- ----------------------------------------------------------------------------
-- 2. TABLA: departamentos
-- Clasificación y familias de productos y servicios.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departamentos (
    id TEXT PRIMARY KEY NOT NULL,
    nombre TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);

-- ----------------------------------------------------------------------------
-- 3. TABLA: productos
-- Catálogo con Multi-Precio (Público, Cerrajero, Taller, Mayoreo) y BOM.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    id TEXT PRIMARY KEY NOT NULL,
    codigo_barras TEXT UNIQUE,
    sku TEXT UNIQUE,
    nombre TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    marca TEXT,
    codigo_equivalencia TEXT,
    ubicacion TEXT,
    precio_compra REAL NOT NULL DEFAULT 0.0,
    precio_venta REAL NOT NULL,          -- Nivel 1: Público Casual
    precio_cerrajero REAL,               -- Nivel 2: Gremio Cerrajero
    precio_taller REAL,                  -- Nivel 3: Taller Automotriz
    porcentaje_impuesto REAL NOT NULL DEFAULT 0.0,
    departamento TEXT DEFAULT 'General',
    stock_actual REAL NOT NULL DEFAULT 0.0,
    stock_minimo REAL NOT NULL DEFAULT 5.0,
    es_a_granel INTEGER NOT NULL DEFAULT 0 CHECK (es_a_granel IN (0, 1)),
    cantidad_mayoreo REAL,               -- Nivel 4: Volumen
    precio_mayoreo REAL,
    es_servicio INTEGER NOT NULL DEFAULT 0 CHECK (es_servicio IN (0, 1)),
    insumo_vinculado_id TEXT,
    cantidad_insumo REAL NOT NULL DEFAULT 1.0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (insumo_vinculado_id) REFERENCES productos(id) ON DELETE SET NULL
);

-- ----------------------------------------------------------------------------
-- 4. TABLA: ventas
-- Transacciones de venta guardadas localmente de manera atómica.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ventas (
    id TEXT PRIMARY KEY NOT NULL,
    corte_caja_id TEXT NOT NULL,
    folio_ticket TEXT,
    subtotal REAL NOT NULL,
    descuento_total REAL NOT NULL DEFAULT 0.0,
    impuestos_total REAL NOT NULL DEFAULT 0.0,
    total REAL NOT NULL,
    pagos_desglose TEXT NOT NULL,
    fecha_venta TEXT NOT NULL,
    estatus TEXT NOT NULL DEFAULT 'completado' CHECK (estatus IN ('completado', 'cancelado')),
    FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 5. TABLA: detalles_venta
-- Partidas cobradas con niveles de precio congelados.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS detalles_venta (
    id TEXT PRIMARY KEY NOT NULL,
    venta_id TEXT NOT NULL,
    producto_id TEXT NOT NULL,
    cantidad REAL NOT NULL,
    precio_historico REAL NOT NULL,
    costo_historico REAL NOT NULL DEFAULT 0.0,
    descuento_linea REAL NOT NULL DEFAULT 0.0,
    total_linea REAL NOT NULL,
    FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 6. TABLA: sync_queue (Patrón Outbox)
-- Registro de eventos a despachar asíncronamente hacia el backend.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_queue (
    id TEXT PRIMARY KEY NOT NULL,
    event_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    error_code TEXT,
    created_at TEXT NOT NULL,
    synced_at TEXT
);

-- ----------------------------------------------------------------------------
-- 7. TABLA: usuarios (RBAC y Matriz de Permisos Granulares)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id TEXT PRIMARY KEY NOT NULL,
    nombre TEXT NOT NULL,
    pin_acceso TEXT NOT NULL UNIQUE,
    rol TEXT NOT NULL CHECK (rol IN ('admin', 'cajero')),
    permisos TEXT,                       -- JSON con matriz detallada de permisos
    activo INTEGER NOT NULL DEFAULT 1 CHECK (activo IN (0, 1))
);

-- ----------------------------------------------------------------------------
-- 8. TABLA: clientes Y abonos_credito (Con preparación para Facturación CFDI)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
    id TEXT PRIMARY KEY NOT NULL,
    nombre TEXT NOT NULL,
    rfc_o_dni TEXT,
    regimen_fiscal TEXT,
    uso_cfdi TEXT,
    codigo_postal TEXT,
    correo TEXT,
    telefono TEXT,
    direccion TEXT,
    limite_credito REAL NOT NULL DEFAULT 0.0,
    saldo_deudor REAL NOT NULL DEFAULT 0.0,
    tarifa_preferencial TEXT NOT NULL DEFAULT 'Público', -- Público, Cerrajero, Taller
    activo INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS abonos_credito (
    id TEXT PRIMARY KEY NOT NULL,
    cliente_id TEXT NOT NULL,
    corte_caja_id TEXT NOT NULL,
    monto REAL NOT NULL,
    fecha TEXT NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 9. TABLA: movimientos_caja (ENTRADAS / SALIDAS / GASTOS)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimientos_caja (
    id TEXT PRIMARY KEY NOT NULL,
    corte_caja_id TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('entrada', 'salida')),
    monto REAL NOT NULL,
    concepto TEXT NOT NULL,
    fecha TEXT NOT NULL,
    FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 10. TABLA: movimientos_inventario (KARDEX LOCAL DE STOCK)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS movimientos_inventario (
    id TEXT PRIMARY KEY NOT NULL,
    producto_id TEXT NOT NULL,
    producto_desc TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION')),
    cantidad REAL NOT NULL,
    stock_anterior REAL NOT NULL,
    stock_nuevo REAL NOT NULL,
    usuario_id TEXT NOT NULL,
    departamento TEXT,
    motivo TEXT,
    fecha TEXT NOT NULL,
    created_at TEXT NOT NULL
);

-- ----------------------------------------------------------------------------
-- 11. TABLA: app_metadata & configuracion_negocio
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS configuracion_negocio (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- ============================================================================
-- ÍNDICES DE RENDIMIENTO Y LATENCIA CERO
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_productos_codigo_barras ON productos(codigo_barras);
CREATE INDEX IF NOT EXISTS idx_productos_sku ON productos(sku);
CREATE INDEX IF NOT EXISTS idx_productos_equivalencia ON productos(codigo_equivalencia);
CREATE INDEX IF NOT EXISTS idx_productos_nombre ON productos(nombre);
CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos(marca);

CREATE INDEX IF NOT EXISTS idx_mov_inv_prod ON movimientos_inventario(producto_id);
CREATE INDEX IF NOT EXISTS idx_mov_inv_fecha ON movimientos_inventario(fecha);

CREATE INDEX IF NOT EXISTS idx_sync_queue_status_created ON sync_queue(sync_status, created_at);
CREATE INDEX IF NOT EXISTS idx_ventas_corte_id ON ventas(corte_caja_id);
CREATE INDEX IF NOT EXISTS idx_detalles_venta_venta_id ON detalles_venta(venta_id);
CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes(nombre);
CREATE INDEX IF NOT EXISTS idx_movimientos_corte_id ON movimientos_caja(corte_caja_id);