-- =====================================================================
-- 07_tests.sql
-- Tests for the DEMO: run each block separately
-- (select the lines and press Ctrl+Enter in Workbench).
-- IMPORTANT: steps (a), (b) and (c) must run in the SAME Workbench tab.
-- =====================================================================
USE mexico_inflation;

-- ---------- 1) REPORTS (views) ----------
SELECT * FROM vw_report_annual_inflation WHERE indicator = 'Headline CPI' ORDER BY period_date;
SELECT * FROM vw_report_indicator_summary;
SELECT * FROM vw_report_core_vs_noncore ORDER BY period_date;

-- ---------- 2) STORED PROCEDURES ----------
CALL sp_list_indicators();
CALL sp_get_by_period(2026, 10);
CALL sp_get_history('Headline CPI', 'Annual');
CALL sp_get_latest_inflation();
CALL sp_top_inflation_months('Headline CPI', 3);
CALL sp_purchasing_power(1000);

-- ---------- 3) AUDIT with triggers ----------
-- (a) Register a new data point  -> creates an INSERT row in audit_log
CALL sp_register_observation(865565, 2026, 11, 3.90);
-- (b) Correct it                 -> creates an UPDATE row in audit_log
SET @new_id = (SELECT o.observation_id FROM observation o
               JOIN period p ON p.period_id = o.period_id
               WHERE o.series_id = 865565 AND p.period_year = 2026 AND p.period_month = 11);
CALL sp_update_observation(@new_id, 4.05);
-- (c) Delete it                  -> creates a DELETE row in audit_log
CALL sp_delete_observation(@new_id);
-- (d) Read the audit log
SELECT audit_id, table_name, operation, record_id, old_data, new_data, db_user, event_time
FROM audit_log ORDER BY audit_id DESC;

-- ---------- 4) VALIDATIONS (they must show an ERROR on purpose) ----------
CALL sp_register_observation(999999, 2026, 11, 3.90);    -- series does not exist
CALL sp_register_observation(865565, 2026, 13, 3.90);    -- invalid month
CALL sp_register_observation(865565, 2026, 11, 5000);    -- value out of range

-- ---------- 5) ROLES ----------
-- Create 3 new connections in Workbench (the + button next to "MySQL Connections"):
--   admin_inflation / analyst_inflation / user_inflation  (passwords are in 06_roles_and_permissions.sql)
-- With each one, run these lines and compare what works and what says "command denied":
SELECT CURRENT_USER(), CURRENT_ROLE();
SELECT * FROM mexico_inflation.vw_report_annual_inflation LIMIT 3;   -- admin OK  analyst OK  user OK
SELECT * FROM mexico_inflation.observation LIMIT 3;                  -- admin OK  analyst OK  user DENIED
SELECT * FROM mexico_inflation.audit_log LIMIT 3;                    -- admin OK  analyst DENIED  user DENIED
CALL mexico_inflation.sp_delete_observation(0);                      -- admin runs it (replies "does not exist")  analyst DENIED  user DENIED
