DROP INDEX IF EXISTS idx_ventas_cliente_id;
ALTER TABLE ventas DROP COLUMN IF EXISTS cliente_nombre;
ALTER TABLE ventas DROP COLUMN IF EXISTS cliente_id;
