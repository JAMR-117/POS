-- Habilitar extensión UUID para generación de llaves si no provienen del cliente
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1. SUCURSALES / TIENDAS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tiendas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clave VARCHAR(32) NOT NULL UNIQUE,
    nombre VARCHAR(120) NOT NULL,
    direccion TEXT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. USUARIOS Y CONTROL DE ACCESO (RBAC)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tienda_id UUID REFERENCES tiendas(id) ON DELETE SET NULL,
    username VARCHAR(64) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nombre_completo VARCHAR(120) NOT NULL,
    rol VARCHAR(20) NOT NULL CHECK (rol IN ('admin', 'cajero')),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_usuarios_tienda ON usuarios(tienda_id);

-- ----------------------------------------------------------------------------
-- 3. CATÁLOGO MAESTRO DE PRODUCTOS
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS productos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tienda_id UUID NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
    codigo_barras VARCHAR(64),
    sku VARCHAR(64),
    descripcion VARCHAR(255) NOT NULL,
    precio_compra NUMERIC(12, 4) NOT NULL DEFAULT 0.0000,
    precio_venta NUMERIC(12, 4) NOT NULL,
    porcentaje_impuesto NUMERIC(5, 4) NOT NULL DEFAULT 0.0000,
    departamento VARCHAR(64) DEFAULT 'General',
    stock_actual NUMERIC(12, 3) NOT NULL DEFAULT 0.000, -- Soporte para venta fraccionada/granel
    es_a_granel BOOLEAN NOT NULL DEFAULT FALSE,
    -- Métricas de venta para ordenamiento y alertas predictivas (BI Fase 5)
    total_unidades_vendidas NUMERIC(14, 3) NOT NULL DEFAULT 0.000,
    ventas_ultimos_30dias NUMERIC(14, 3) NOT NULL DEFAULT 0.000,
    ultima_venta_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_productos_tienda_barcode UNIQUE (tienda_id, codigo_barras),
    CONSTRAINT uq_productos_tienda_sku UNIQUE (tienda_id, sku)
);

CREATE INDEX IF NOT EXISTS idx_productos_busqueda ON productos(tienda_id, codigo_barras, sku);
CREATE INDEX IF NOT EXISTS idx_productos_rotacion ON productos(tienda_id, ventas_ultimos_30dias DESC);

-- ----------------------------------------------------------------------------
-- 4. CONSOLIDACIÓN DE CORTES DE CAJA (TURNOS X Y Z)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cortes_caja (
    id UUID PRIMARY KEY, -- Mapeado directo del UUID cliente
    tienda_id UUID NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
    terminal_id VARCHAR(64) NOT NULL,
    usuario_id UUID NOT NULL REFERENCES usuarios(id) ON DELETE RESTRICT,
    folio_corte INT,
    monto_inicial NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    monto_ventas_efectivo NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    monto_ventas_tarjeta NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    monto_ventas_otros NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    monto_retiros NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    tipo_corte VARCHAR(2) NOT NULL CHECK (tipo_corte IN ('X', 'Z')),
    discrepancia NUMERIC(12, 2) DEFAULT 0.00,
    fecha_apertura TIMESTAMPTZ NOT NULL,
    fecha_cierre TIMESTAMPTZ,
    estado VARCHAR(16) NOT NULL DEFAULT 'cerrado',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cortes_tienda_terminal ON cortes_caja(tienda_id, terminal_id, fecha_apertura);

-- ----------------------------------------------------------------------------
-- 5. VENTAS Y DETALLES DE VENTA
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ventas (
    id UUID PRIMARY KEY, -- Mapeado directo del venta_id emitido por SQLite
    tienda_id UUID NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
    terminal_id VARCHAR(64) NOT NULL,
    corte_caja_id UUID REFERENCES cortes_caja(id) ON DELETE SET NULL,
    folio_ticket VARCHAR(64),
    subtotal NUMERIC(12, 2) NOT NULL,
    descuento_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    impuestos_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total NUMERIC(12, 2) NOT NULL,
    pagos_desglose JSONB NOT NULL,
    fecha_venta TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ventas_tienda_fecha ON ventas(tienda_id, fecha_venta DESC);

CREATE TABLE IF NOT EXISTS detalles_venta (
    id UUID PRIMARY KEY,
    venta_id UUID NOT NULL REFERENCES ventas(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES productos(id) ON DELETE RESTRICT,
    cantidad NUMERIC(12, 3) NOT NULL,
    precio_historico NUMERIC(12, 4) NOT NULL,
    costo_historico NUMERIC(12, 4) NOT NULL DEFAULT 0.0000,
    descuento_linea NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_linea NUMERIC(12, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_detalles_venta_id ON detalles_venta(venta_id);
CREATE INDEX IF NOT EXISTS idx_detalles_producto_id ON detalles_venta(producto_id);

-- ----------------------------------------------------------------------------
-- 6. TABLA DE IDEMPOTENCIA (SYNC_EVENTS_PROCESSED)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_events_processed (
    event_id VARCHAR(64) NOT NULL,
    terminal_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (event_id, terminal_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_processed_at ON sync_events_processed(processed_at);