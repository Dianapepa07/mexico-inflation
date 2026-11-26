-- =====================================================================
-- 01_create_database_and_tables.sql
-- Project: Inflation in Mexico (INEGI data)
-- What it does: creates the database, the 7 normalized entities, the audit
--               table and the initial catalog data (roles, variation types, demo users).
-- Where to run it: MySQL Workbench (File > Open SQL Script > lightning bolt)
-- Order: THIS IS THE FIRST SCRIPT. Then run python/load_data.py
-- WARNING: it drops and recreates the database (you can re-run it to start over).
-- =====================================================================

DROP DATABASE IF EXISTS mexico_inflation;
CREATE DATABASE mexico_inflation
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mexico_inflation;

-- ---------------------------------------------------------------------
-- ENTITY 1: role  (application roles: Administrator, Analyst, User)
-- ---------------------------------------------------------------------
CREATE TABLE role (
    role_id      TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name         VARCHAR(30)  NOT NULL,
    description  VARCHAR(150) NULL,
    PRIMARY KEY (role_id),
    UNIQUE KEY uq_role_name (name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 2: app_user  (people who use the system; each one has ONE role)
-- ---------------------------------------------------------------------
CREATE TABLE app_user (
    user_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name   VARCHAR(80)  NOT NULL,
    email       VARCHAR(120) NOT NULL,
    role_id     TINYINT UNSIGNED NOT NULL,
    is_active   TINYINT(1)   NOT NULL DEFAULT 1,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_app_user_email (email),
    CONSTRAINT fk_app_user_role FOREIGN KEY (role_id)
        REFERENCES role (role_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 3: indicator  (what is measured: Headline CPI, Core, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE indicator (
    indicator_id  SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name          VARCHAR(80)  NOT NULL,
    description   VARCHAR(255) NULL,
    PRIMARY KEY (indicator_id),
    UNIQUE KEY uq_indicator_name (name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 4: variation_type  (how it is measured: Monthly, Year to date, Annual)
-- ---------------------------------------------------------------------
CREATE TABLE variation_type (
    variation_type_id  TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name               VARCHAR(40)  NOT NULL,
    description        VARCHAR(150) NULL,
    PRIMARY KEY (variation_type_id),
    UNIQUE KEY uq_variation_type_name (name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 5: series  (each column of the INEGI CSV = one indicator + one variation type)
-- series_id is the official INEGI id (e.g. 865565), so it is NOT AUTO_INCREMENT.
-- ---------------------------------------------------------------------
CREATE TABLE series (
    series_id          INT UNSIGNED NOT NULL,
    indicator_id       SMALLINT UNSIGNED NOT NULL,
    variation_type_id  TINYINT UNSIGNED  NOT NULL,
    available_from     DATE         NOT NULL,
    available_to       DATE         NOT NULL,
    base               VARCHAR(80)  NOT NULL,
    PRIMARY KEY (series_id),
    UNIQUE KEY uq_series_indicator_type (indicator_id, variation_type_id),
    CONSTRAINT fk_series_indicator FOREIGN KEY (indicator_id)
        REFERENCES indicator (indicator_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_series_variation_type FOREIGN KEY (variation_type_id)
        REFERENCES variation_type (variation_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 6: period  (one calendar month)
-- period_date is a GENERATED column: MySQL computes it from period_year and period_month.
-- ---------------------------------------------------------------------
CREATE TABLE period (
    period_id     SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    period_year   SMALLINT UNSIGNED NOT NULL,
    period_month  TINYINT UNSIGNED  NOT NULL,
    period_date   DATE GENERATED ALWAYS AS
                  (DATE_ADD(MAKEDATE(period_year, 1), INTERVAL (period_month - 1) MONTH)) STORED,
    PRIMARY KEY (period_id),
    UNIQUE KEY uq_period_year_month (period_year, period_month),
    CONSTRAINT ck_period_month CHECK (period_month BETWEEN 1 AND 12)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- ENTITY 7: observation  (the data point: value of one series in one period)
-- value_pct is the percentage variation published by INEGI (e.g. 3.75 means 3.75 %).
-- ---------------------------------------------------------------------
CREATE TABLE observation (
    observation_id  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    series_id       INT UNSIGNED      NOT NULL,
    period_id       SMALLINT UNSIGNED NOT NULL,
    value_pct       DECIMAL(20,12)    NOT NULL,
    loaded_at       DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (observation_id),
    UNIQUE KEY uq_observation_series_period (series_id, period_id),
    KEY idx_observation_period (period_id),
    CONSTRAINT fk_observation_series FOREIGN KEY (series_id)
        REFERENCES series (series_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_observation_period FOREIGN KEY (period_id)
        REFERENCES period (period_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- AUDIT TABLE (not a business entity; it is filled by TRIGGERS)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    table_name   VARCHAR(64)  NOT NULL,
    operation    ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    record_id    VARCHAR(64)  NOT NULL,
    old_data     JSON NULL,
    new_data     JSON NULL,
    db_user      VARCHAR(128) NOT NULL,
    event_time   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (audit_id),
    KEY idx_audit_table_time (table_name, event_time)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- INITIAL CATALOG DATA
-- ---------------------------------------------------------------------
INSERT INTO role (name, description) VALUES
    ('Administrator', 'Full control of the database'),
    ('Analyst',       'Reads data, views and reports; can register and correct observations'),
    ('User',          'Read-only access to the public reports');

INSERT INTO variation_type (name, description) VALUES
    ('Monthly',      'Percentage change versus the previous month'),
    ('Year to date', 'Percentage change accumulated since December of the previous year'),
    ('Annual',       'Percentage change versus the same month of the previous year');

-- Demo users (change them if you want)
INSERT INTO app_user (full_name, email, role_id) VALUES
    ('Demo Admin',   'admin@inflation.mx',   1),
    ('Demo Analyst', 'analyst@inflation.mx', 2),
    ('Demo User',    'user@inflation.mx',    3);

SELECT 'Database and tables created successfully' AS result;
