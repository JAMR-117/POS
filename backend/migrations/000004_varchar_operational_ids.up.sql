-- Migración 000004: Convertir IDs operacionales a VARCHAR(64) para compatibilidad total con SQLite / clientes offline

ALTER TABLE detalles_venta DROP CONSTRAINT IF EXISTS detalles_venta_venta_id_fkey;
ALTER TABLE movimientos_caja DROP CONSTRAINT IF EXISTS movimientos_caja_corte_caja_id_fkey;

ALTER TABLE ventas ALTER COLUMN id TYPE VARCHAR(64);
ALTER TABLE ventas ALTER COLUMN corte_caja_id TYPE VARCHAR(64);

ALTER TABLE detalles_venta ALTER COLUMN id TYPE VARCHAR(64);
ALTER TABLE detalles_venta ALTER COLUMN venta_id TYPE VARCHAR(64);

ALTER TABLE cortes_caja ALTER COLUMN id TYPE VARCHAR(64);

ALTER TABLE movimientos_caja ALTER COLUMN id TYPE VARCHAR(64);
ALTER TABLE movimientos_caja ALTER COLUMN corte_caja_id TYPE VARCHAR(64);

ALTER TABLE movimientos_inventario ALTER COLUMN id TYPE VARCHAR(64);

ALTER TABLE detalles_venta ADD CONSTRAINT detalles_venta_venta_id_fkey 
    FOREIGN KEY (venta_id) REFERENCES ventas(id) ON DELETE CASCADE;

ALTER TABLE movimientos_caja ADD CONSTRAINT movimientos_caja_corte_caja_id_fkey 
    FOREIGN KEY (corte_caja_id) REFERENCES cortes_caja(id) ON DELETE RESTRICT;
