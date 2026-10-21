-- Migración de Cerrajería y Módulos de Operación Avanzada POS

-- 1. Actualización de Columnas de Cerrajería en productos
ALTER TABLE productos ADD COLUMN IF NOT EXISTS nombre VARCHAR(255) DEFAULT '';
ALTER TABLE productos ADD COLUMN IF NOT EXISTS marca VARCHAR(100) DEFAULT '';
ALTER TABLE productos ADD COLUMN IF NOT EXISTS codigo_equivalencia VARCHAR(64);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS ubicacion VARCHAR(64);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS precio_cerrajero NUMERIC(12, 4);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS precio_taller NUMERIC(12, 4);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS precio_mayoreo NUMERIC(12, 4);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS cantidad_mayoreo NUMERIC(12, 3);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS stock_minimo NUMERIC(12, 3) DEFAULT 5.000;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS es_servicio INT DEFAULT 0;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS insumo_vinculado_id UUID REFERENCES productos(id) ON DELETE SET NULL;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS cantidad_insumo NUMERIC(12, 3) DEFAULT 1.000;

CREATE INDEX IF NOT EXISTS idx_productos_equivalencia ON productos(tienda_id, codigo_equivalencia);
CREATE INDEX IF NOT EXISTS idx_productos_ubicacion ON productos(tienda_id, ubicacion);

-- 2. Tabla de Kardex / Movimientos de Inventario
CREATE TABLE IF NOT EXISTS movimientos_inventario (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    producto_id UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    tipo VARCHAR(32) NOT NULL, -- 'VENTA', 'ENTRADA', 'AJUSTE', 'DEVOLUCION', 'VENTA_SERVICIO'
    cantidad NUMERIC(12, 3) NOT NULL,
    stock_anterior NUMERIC(12, 3) NOT NULL,
    stock_nuevo NUMERIC(12, 3) NOT NULL,
    referencia_id VARCHAR(64),
    motivo TEXT,
    usuario VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mov_inv_prod ON movimientos_inventario(producto_id);
CREATE INDEX IF NOT EXISTS idx_mov_inv_fecha ON movimientos_inventario(created_at DESC);

-- 3. Tabla de Movimientos de Caja (Entradas / Retiros)
CREATE TABLE IF NOT EXISTS movimientos_caja (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    corte_caja_id UUID REFERENCES cortes_caja(id) ON DELETE SET NULL,
    terminal_id VARCHAR(64),
    tipo VARCHAR(32) NOT NULL, -- 'ENTRADA', 'SALIDA'
    monto NUMERIC(12, 2) NOT NULL,
    concepto TEXT NOT NULL,
    usuario VARCHAR(64),
    fecha TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mov_caja_corte ON movimientos_caja(corte_caja_id);

-- 4. Tabla de Clientes y Catálogo de Crédito
CREATE TABLE IF NOT EXISTS clientes (
    id VARCHAR(64) PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    telefono VARCHAR(32),
    email VARCHAR(128),
    rfc VARCHAR(32),
    direccion TEXT,
    limite_credito NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    saldo_deudor NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    nivel_precio VARCHAR(32) NOT NULL DEFAULT 'Público',
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Asegurar Sucursal Matriz y Flexibilidad de Cortes de Caja
ALTER TABLE ventas DROP CONSTRAINT IF EXISTS ventas_corte_caja_id_fkey;

INSERT INTO tiendas (id, clave, nombre, activo) 
VALUES ('8377312b-9a2a-4d0f-b74d-f2e0ca6c4d2a', 'SUC-001', 'Tienda Principal', true) 
ON CONFLICT (clave) DO NOTHING;
