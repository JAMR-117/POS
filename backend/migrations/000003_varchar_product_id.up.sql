-- 000003_varchar_product_id.up.sql
-- Flexibilidad completa de identificadores de productos y detalles de venta para SQLite y CSV

BEGIN;
ALTER TABLE detalles_venta DROP CONSTRAINT IF EXISTS detalles_venta_producto_id_fkey;
ALTER TABLE movimientos_inventario DROP CONSTRAINT IF EXISTS movimientos_inventario_producto_id_fkey;
ALTER TABLE productos DROP CONSTRAINT IF EXISTS productos_insumo_vinculado_id_fkey;

ALTER TABLE productos ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
ALTER TABLE productos ALTER COLUMN insumo_vinculado_id TYPE VARCHAR(64) USING insumo_vinculado_id::text;
ALTER TABLE detalles_venta ALTER COLUMN producto_id TYPE VARCHAR(64) USING producto_id::text;
ALTER TABLE movimientos_inventario ALTER COLUMN producto_id TYPE VARCHAR(64) USING producto_id::text;

ALTER TABLE detalles_venta ADD CONSTRAINT detalles_venta_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE RESTRICT;
ALTER TABLE movimientos_inventario ADD CONSTRAINT movimientos_inventario_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES productos(id) ON DELETE CASCADE;
ALTER TABLE productos ADD CONSTRAINT productos_insumo_vinculado_id_fkey FOREIGN KEY (insumo_vinculado_id) REFERENCES productos(id) ON DELETE SET NULL;
COMMIT;
