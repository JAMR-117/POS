-- =============================================================================
-- MIGRACIÓN 000006: TRAZABILIDAD DE CLIENTE Y ESTADO DE CUENTA EN VENTAS
-- =============================================================================

ALTER TABLE ventas
    ADD COLUMN IF NOT EXISTS cliente_id VARCHAR(64) DEFAULT 'PUBLICO-GRAL',
    ADD COLUMN IF NOT EXISTS cliente_nombre VARCHAR(255) DEFAULT 'Público en General';

CREATE INDEX IF NOT EXISTS idx_ventas_cliente_id
    ON ventas(cliente_id);
