-- dsiprouter_call_limit.sql
-- Configuración de límite de llamadas concurrentes vía dSIPRouter
-- dSIPRouter inyecta esto al runtime de Kamailio htable

-- Tabla principal
CREATE TABLE IF NOT EXISTS dsip_call_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    gwgroupid INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    limit_calls INT NOT NULL DEFAULT 0,
    time_period INT NOT NULL DEFAULT 0,        -- 0=concurrent; >0=per period
    mode TINYINT NOT NULL DEFAULT 1,           -- 1=block, 2=route alt, 3=defer
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_gw_name (gwgroupid, name)
);

-- Ejemplos: límites por cliente
INSERT INTO dsip_call_settings (gwgroupid, name, limit_calls, time_period, mode)
VALUES
    (1001, 'cliente_premium',  500, 0, 1),    -- 500 conc, block on excess
    (1002, 'cliente_standard', 100, 0, 1),
    (1003, 'cliente_pyme',      30, 0, 1),
    (9999, 'fraud_blacklist',    0, 0, 1);    -- 0 = bloqueo total

-- Verificar después de reload Kamailio:
--   kamcmd htable.dump call_limits
