DROP INDEX IF EXISTS idx_detalles_venta_insumo_utilizado;

ALTER TABLE detalles_venta
    DROP COLUMN IF EXISTS cantidad_insumo_consumida,
    DROP COLUMN IF EXISTS insumo_utilizado_id;

ALTER TABLE productos
    DROP COLUMN IF EXISTS departamentos_aplicables;
