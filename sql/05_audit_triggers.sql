-- =====================================================================
-- 05_audit_triggers.sql
-- Triggers: they run AUTOMATICALLY when someone does INSERT / UPDATE / DELETE
-- and store a copy of the change in the 'audit_log' table.
-- Audited tables: observation, indicator, app_user  (9 triggers)
-- Order: run it AFTER loading the data with Python, so the audit log only
--        records the changes made from now on.
-- Note: triggers run with the privileges of whoever created them, so an Analyst
--       can fire the audit even without direct permission on 'audit_log'.
-- =====================================================================
USE mexico_inflation;

DROP TRIGGER IF EXISTS trg_observation_ai;
DROP TRIGGER IF EXISTS trg_observation_au;
DROP TRIGGER IF EXISTS trg_observation_ad;
DROP TRIGGER IF EXISTS trg_indicator_ai;
DROP TRIGGER IF EXISTS trg_indicator_au;
DROP TRIGGER IF EXISTS trg_indicator_ad;
DROP TRIGGER IF EXISTS trg_app_user_ai;
DROP TRIGGER IF EXISTS trg_app_user_au;
DROP TRIGGER IF EXISTS trg_app_user_ad;

DELIMITER $$

-- ------------------------------ OBSERVATION ------------------------------
CREATE TRIGGER trg_observation_ai AFTER INSERT ON observation
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('observation', 'INSERT', NEW.observation_id, NULL,
            JSON_OBJECT('series_id', NEW.series_id, 'period_id', NEW.period_id, 'value_pct', NEW.value_pct),
            USER());
END$$

CREATE TRIGGER trg_observation_au AFTER UPDATE ON observation
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('observation', 'UPDATE', NEW.observation_id,
            JSON_OBJECT('series_id', OLD.series_id, 'period_id', OLD.period_id, 'value_pct', OLD.value_pct),
            JSON_OBJECT('series_id', NEW.series_id, 'period_id', NEW.period_id, 'value_pct', NEW.value_pct),
            USER());
END$$

CREATE TRIGGER trg_observation_ad AFTER DELETE ON observation
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('observation', 'DELETE', OLD.observation_id,
            JSON_OBJECT('series_id', OLD.series_id, 'period_id', OLD.period_id, 'value_pct', OLD.value_pct),
            NULL, USER());
END$$

-- ------------------------------ INDICATOR ------------------------------
CREATE TRIGGER trg_indicator_ai AFTER INSERT ON indicator
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('indicator', 'INSERT', NEW.indicator_id, NULL,
            JSON_OBJECT('name', NEW.name, 'description', NEW.description),
            USER());
END$$

CREATE TRIGGER trg_indicator_au AFTER UPDATE ON indicator
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('indicator', 'UPDATE', NEW.indicator_id,
            JSON_OBJECT('name', OLD.name, 'description', OLD.description),
            JSON_OBJECT('name', NEW.name, 'description', NEW.description),
            USER());
END$$

CREATE TRIGGER trg_indicator_ad AFTER DELETE ON indicator
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('indicator', 'DELETE', OLD.indicator_id,
            JSON_OBJECT('name', OLD.name, 'description', OLD.description),
            NULL, USER());
END$$

-- ------------------------------ APP_USER ------------------------------
CREATE TRIGGER trg_app_user_ai AFTER INSERT ON app_user
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('app_user', 'INSERT', NEW.user_id, NULL,
            JSON_OBJECT('full_name', NEW.full_name, 'email', NEW.email, 'role_id', NEW.role_id, 'is_active', NEW.is_active),
            USER());
END$$

CREATE TRIGGER trg_app_user_au AFTER UPDATE ON app_user
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('app_user', 'UPDATE', NEW.user_id,
            JSON_OBJECT('full_name', OLD.full_name, 'email', OLD.email, 'role_id', OLD.role_id, 'is_active', OLD.is_active),
            JSON_OBJECT('full_name', NEW.full_name, 'email', NEW.email, 'role_id', NEW.role_id, 'is_active', NEW.is_active),
            USER());
END$$

CREATE TRIGGER trg_app_user_ad AFTER DELETE ON app_user
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, db_user)
    VALUES ('app_user', 'DELETE', OLD.user_id,
            JSON_OBJECT('full_name', OLD.full_name, 'email', OLD.email, 'role_id', OLD.role_id, 'is_active', OLD.is_active),
            NULL, USER());
END$$

DELIMITER ;

SELECT TRIGGER_NAME, EVENT_MANIPULATION AS event, EVENT_OBJECT_TABLE AS table_name
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'mexico_inflation'
ORDER BY EVENT_OBJECT_TABLE, EVENT_MANIPULATION;
