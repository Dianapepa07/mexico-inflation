-- =====================================================================
-- 02_functions.sql
-- Stored functions (they return ONE value and are used inside a SELECT).
-- Order: run it AFTER loading the data with Python.
-- =====================================================================
USE mexico_inflation;

DROP FUNCTION IF EXISTS fn_classify_inflation;
DROP FUNCTION IF EXISTS fn_real_value;

DELIMITER $$

-- Classifies an ANNUAL inflation rate against the Banco de México target:
-- 3 % with a variability interval of +/- 1 point (that is, from 2 % to 4 %).
CREATE FUNCTION fn_classify_inflation(p_value DECIMAL(20,12))
RETURNS VARCHAR(25)
DETERMINISTIC
BEGIN
    IF p_value IS NULL THEN
        RETURN 'No data';
    ELSEIF p_value < 2 THEN
        RETURN 'Below target';
    ELSEIF p_value <= 4 THEN
        RETURN 'Within target';
    ELSEIF p_value <= 6 THEN
        RETURN 'Elevated';
    ELSE
        RETURN 'High';
    END IF;
END$$

-- Purchasing power: what an amount from one year ago is "worth today" given annual inflation.
-- Example: fn_real_value(1000, 3.75) = 963.86
CREATE FUNCTION fn_real_value(p_amount DECIMAL(14,2), p_inflation_pct DECIMAL(20,12))
RETURNS DECIMAL(14,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_amount / (1 + p_inflation_pct / 100), 2);
END$$

DELIMITER ;

SELECT fn_classify_inflation(3.75) AS classification_test, fn_real_value(1000, 3.75) AS real_value_test;
