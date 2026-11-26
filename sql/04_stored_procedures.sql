-- =====================================================================
-- 04_stored_procedures.sql
-- Stored procedures. They are executed with CALL procedure_name(...)
--   A) Business queries ........ sp_list_indicators, sp_get_by_period, sp_get_history,
--                                sp_get_latest_inflation, sp_top_inflation_months,
--                                sp_purchasing_power
--   B) Validated writes ........ sp_register_observation, sp_update_observation,
--                                sp_delete_observation
--   C) Reads for MongoDB ....... getAll<Table>  (used by python/migrate_to_mongo.py)
-- =====================================================================
USE mexico_inflation;

DROP PROCEDURE IF EXISTS sp_list_indicators;
DROP PROCEDURE IF EXISTS sp_get_by_period;
DROP PROCEDURE IF EXISTS sp_get_history;
DROP PROCEDURE IF EXISTS sp_get_latest_inflation;
DROP PROCEDURE IF EXISTS sp_top_inflation_months;
DROP PROCEDURE IF EXISTS sp_purchasing_power;
DROP PROCEDURE IF EXISTS sp_register_observation;
DROP PROCEDURE IF EXISTS sp_update_observation;
DROP PROCEDURE IF EXISTS sp_delete_observation;
DROP PROCEDURE IF EXISTS getAllRole;
DROP PROCEDURE IF EXISTS getAllApp_user;
DROP PROCEDURE IF EXISTS getAllIndicator;
DROP PROCEDURE IF EXISTS getAllVariation_type;
DROP PROCEDURE IF EXISTS getAllSeries;
DROP PROCEDURE IF EXISTS getAllPeriod;
DROP PROCEDURE IF EXISTS getAllObservation;
DROP PROCEDURE IF EXISTS getAllAudit_log;

DELIMITER $$

-- ============================ A) QUERIES ============================

-- Lists the available indicators
CREATE PROCEDURE sp_list_indicators()
BEGIN
    SELECT indicator_id, name, description
    FROM indicator
    ORDER BY indicator_id;
END$$

-- All indicators for one month. Example: CALL sp_get_by_period(2026, 10);
CREATE PROCEDURE sp_get_by_period(IN p_year SMALLINT, IN p_month TINYINT)
BEGIN
    SELECT indicator, variation_type, ROUND(value_pct, 4) AS value_pct
    FROM vw_inflation_detail
    WHERE period_year = p_year AND period_month = p_month
    ORDER BY indicator, variation_type;
END$$

-- History of one indicator. Example: CALL sp_get_history('Headline CPI', 'Annual');
CREATE PROCEDURE sp_get_history(IN p_indicator VARCHAR(80), IN p_variation VARCHAR(40))
BEGIN
    SELECT period_date, indicator, variation_type, ROUND(value_pct, 4) AS value_pct
    FROM vw_inflation_detail
    WHERE indicator = p_indicator AND variation_type = p_variation
    ORDER BY period_date;
END$$

-- Annual inflation of the latest available month, with its classification
CREATE PROCEDURE sp_get_latest_inflation()
BEGIN
    SELECT period_date, indicator, ROUND(value_pct, 2) AS annual_inflation_pct,
           fn_classify_inflation(value_pct)            AS classification
    FROM vw_inflation_detail
    WHERE variation_type = 'Annual'
      AND period_date = (SELECT MAX(period_date) FROM vw_inflation_detail)   -- latest month that HAS data
    ORDER BY value_pct DESC;
END$$

-- The N months with the highest monthly inflation for an indicator.
-- Example: CALL sp_top_inflation_months('Headline CPI', 3);
CREATE PROCEDURE sp_top_inflation_months(IN p_indicator VARCHAR(80), IN p_limit INT)
BEGIN
    SELECT period_date, indicator, ROUND(value_pct, 4) AS monthly_inflation_pct
    FROM vw_inflation_detail
    WHERE indicator = p_indicator AND variation_type = 'Monthly'
    ORDER BY value_pct DESC
    LIMIT p_limit;
END$$

-- How much is an amount from one year ago worth today? Uses the latest annual Headline CPI.
-- Example: CALL sp_purchasing_power(1000);
CREATE PROCEDURE sp_purchasing_power(IN p_amount DECIMAL(14,2))
BEGIN
    DECLARE v_inflation DECIMAL(20,12);
    DECLARE v_date DATE;

    SELECT value_pct, period_date INTO v_inflation, v_date
    FROM vw_inflation_detail
    WHERE indicator = 'Headline CPI' AND variation_type = 'Annual'
    ORDER BY period_date DESC
    LIMIT 1;

    SELECT p_amount                              AS amount_one_year_ago,
           ROUND(v_inflation, 2)                 AS annual_inflation_pct,
           fn_real_value(p_amount, v_inflation)  AS current_purchasing_power,
           v_date                                AS reference_date;
END$$

-- ====================== B) VALIDATED WRITES ======================

-- Registers (or corrects) a data point. Creates the period if it does not exist yet.
-- Example: CALL sp_register_observation(865565, 2026, 11, 3.90);
CREATE PROCEDURE sp_register_observation(
    IN p_series_id INT UNSIGNED, IN p_year SMALLINT UNSIGNED,
    IN p_month TINYINT UNSIGNED, IN p_value DECIMAL(20,12))
BEGIN
    DECLARE v_period_id SMALLINT UNSIGNED;

    IF NOT EXISTS (SELECT 1 FROM series WHERE series_id = p_series_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: the series does not exist';
    END IF;
    IF p_month < 1 OR p_month > 12 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: the month must be between 1 and 12';
    END IF;
    IF p_value IS NULL OR p_value < -100 OR p_value > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: value out of range (-100 to 1000)';
    END IF;

    INSERT INTO period (period_year, period_month) VALUES (p_year, p_month)
    ON DUPLICATE KEY UPDATE period_year = period_year;

    SELECT period_id INTO v_period_id
    FROM period WHERE period_year = p_year AND period_month = p_month;

    INSERT INTO observation (series_id, period_id, value_pct)
    VALUES (p_series_id, v_period_id, p_value)
    ON DUPLICATE KEY UPDATE value_pct = p_value;

    SELECT 'Observation registered' AS result;
END$$

-- Corrects the value of an existing observation
CREATE PROCEDURE sp_update_observation(IN p_observation_id BIGINT UNSIGNED, IN p_value DECIMAL(20,12))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM observation WHERE observation_id = p_observation_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: the observation does not exist';
    END IF;
    IF p_value IS NULL OR p_value < -100 OR p_value > 1000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: value out of range (-100 to 1000)';
    END IF;

    UPDATE observation SET value_pct = p_value WHERE observation_id = p_observation_id;
    SELECT 'Observation updated' AS result;
END$$

-- Deletes an observation (only the Administrator is allowed to execute it)
CREATE PROCEDURE sp_delete_observation(IN p_observation_id BIGINT UNSIGNED)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM observation WHERE observation_id = p_observation_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: the observation does not exist';
    END IF;

    DELETE FROM observation WHERE observation_id = p_observation_id;
    SELECT 'Observation deleted' AS result;
END$$

-- ===================== C) READS FOR THE MONGODB MIGRATION =====================
-- The migration script calls  getAll + table_name.capitalize()
-- Example: table 'variation_type' -> getAllVariation_type

CREATE PROCEDURE getAllRole()           BEGIN SELECT * FROM role;           END$$
CREATE PROCEDURE getAllApp_user()       BEGIN SELECT * FROM app_user;       END$$
CREATE PROCEDURE getAllIndicator()      BEGIN SELECT * FROM indicator;      END$$
CREATE PROCEDURE getAllVariation_type() BEGIN SELECT * FROM variation_type; END$$
CREATE PROCEDURE getAllSeries()         BEGIN SELECT * FROM series;         END$$
CREATE PROCEDURE getAllPeriod()         BEGIN SELECT * FROM period;         END$$
CREATE PROCEDURE getAllObservation()    BEGIN SELECT * FROM observation;    END$$
CREATE PROCEDURE getAllAudit_log()      BEGIN SELECT * FROM audit_log;      END$$

DELIMITER ;

CALL sp_get_latest_inflation();
