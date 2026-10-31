-- =============================================================================
-- MIGRACIÓN 000005: SERVICIOS CONFIGURABLES POR DEPARTAMENTO Y DESCUENTO DINÁMICO DE INSUMOS (Dynamic Runtime BOM)
-- =============================================================================

ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS departamentos_aplicables TEXT NOT NULL DEFAULT 'Todos';

ALTER TABLE detalles_venta
    ADD COLUMN IF NOT EXISTS insumo_utilizado_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS cantidad_insumo_consumida NUMERIC(12, 3) NOT NULL DEFAULT 0.0;

CREATE INDEX IF NOT EXISTS idx_detalles_venta_insumo_utilizado
    ON detalles_venta(insumo_utilizado_id)
    WHERE insumo_utilizado_id IS NOT NULL;
