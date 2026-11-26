-- =====================================================================
-- 03_views_reports.sql
-- Views: saved queries that are read like tables.
--   vw_inflation_detail ............ base view (joins the 5 data tables)
--   vw_report_annual_inflation ..... REPORT 1: annual inflation with classification
--   vw_report_indicator_summary .... REPORT 2: statistics per indicator
--   vw_report_core_vs_noncore ...... REPORT 3: core vs. non-core inflation
-- =====================================================================
USE mexico_inflation;

-- Base view: all the data already joined and readable
CREATE OR REPLACE VIEW vw_inflation_detail AS
SELECT  o.observation_id,
        p.period_year,
        p.period_month,
        p.period_date,
        i.indicator_id,
        i.name   AS indicator,
        v.name   AS variation_type,
        s.series_id,
        o.value_pct
FROM observation o
JOIN series         s ON s.series_id         = o.series_id
JOIN indicator      i ON i.indicator_id      = s.indicator_id
JOIN variation_type v ON v.variation_type_id = s.variation_type_id
JOIN period         p ON p.period_id         = o.period_id;

-- REPORT 1: How is the annual inflation of each indicator month by month, and at what level?
CREATE OR REPLACE VIEW vw_report_annual_inflation AS
SELECT  period_date,
        period_year,
        period_month,
        indicator,
        ROUND(value_pct, 2)                 AS annual_inflation_pct,
        fn_classify_inflation(value_pct)    AS classification
FROM vw_inflation_detail
WHERE variation_type = 'Annual';

-- REPORT 2: Statistical summary of MONTHLY inflation per indicator
CREATE OR REPLACE VIEW vw_report_indicator_summary AS
SELECT  indicator,
        COUNT(*)                AS months_recorded,
        ROUND(AVG(value_pct), 4) AS avg_monthly_pct,
        ROUND(MIN(value_pct), 4) AS min_monthly_pct,
        ROUND(MAX(value_pct), 4) AS max_monthly_pct,
        MIN(period_date)        AS first_month,
        MAX(period_date)        AS last_month
FROM vw_inflation_detail
WHERE variation_type = 'Monthly'
GROUP BY indicator;

-- REPORT 3: Annual headline vs. core vs. non-core inflation (and the gap between them)
CREATE OR REPLACE VIEW vw_report_core_vs_noncore AS
SELECT  period_date,
        period_year,
        period_month,
        MAX(CASE WHEN indicator = 'Headline CPI' THEN ROUND(value_pct, 2) END) AS headline_cpi_pct,
        MAX(CASE WHEN indicator = 'Core'         THEN ROUND(value_pct, 2) END) AS core_pct,
        MAX(CASE WHEN indicator = 'Non-core'     THEN ROUND(value_pct, 2) END) AS non_core_pct,
        ROUND(MAX(CASE WHEN indicator = 'Non-core' THEN value_pct END)
            - MAX(CASE WHEN indicator = 'Core'     THEN value_pct END), 2)     AS gap_pp
FROM vw_inflation_detail
WHERE variation_type = 'Annual'
GROUP BY period_date, period_year, period_month;

SELECT * FROM vw_report_indicator_summary;
