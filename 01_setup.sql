-- =====================================================================
-- 01_setup.sql
-- Purpose : Create database, schemas, warehouses, roles and grants
--           for the Advanced Education funding analytics demo.
-- Run as  : ACCOUNTADMIN (or equivalent with CREATE privileges)
-- Safe to re-run : YES (idempotent)
-- =====================================================================
 
-- Use an admin role to create account-level objects ------------------
USE ROLE ACCOUNTADMIN;
 
-- ---------------------------------------------------------------------
-- 1. DATABASE
--    One database holds the whole project. Three schemas inside it
--    represent the three layers of the pipeline.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS ADV_EDU
  COMMENT = 'Alberta Advanced Education funding analytics demo';
 
USE DATABASE ADV_EDU;
 
-- ---------------------------------------------------------------------
-- 2. SCHEMAS  (the medallion layers)
--    RAW    = data loaded exactly as it arrives (messy, untouched)
--    SILVER = cleaned & conformed data
--    STAR   = dimensional model for reporting (facts + dimensions)
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS RAW    COMMENT = 'Landing zone - raw CSV loads, no transformation';
CREATE SCHEMA IF NOT EXISTS SILVER COMMENT = 'Cleansed and conformed data';
CREATE SCHEMA IF NOT EXISTS STAR   COMMENT = 'Dimensional model - facts and dimensions';

-- ---------------------------------------------------------------------
-- 3. VIRTUAL WAREHOUSES  (separate compute per workload)
--    Keeping ingestion, transformation and reporting on different
--    warehouses means they never compete for resources. Each one
--    auto-suspends quickly so you only pay while it runs.
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS LOAD_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 60          -- seconds of idle before sleeping
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for ingestion / COPY INTO';

CREATE WAREHOUSE IF NOT EXISTS TRANSFORM_WH
  WAREHOUSE_SIZE = 'SMALL'     -- a little bigger for ELT joins
  AUTO_SUSPEND   = 60
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for ELT / star schema build';
 
CREATE WAREHOUSE IF NOT EXISTS REPORTING_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND   = 120
  AUTO_RESUME    = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for Snowsight / Streamlit / BI queries';
 
-- ---------------------------------------------------------------------
-- 4. ROLES  (functional roles for governed access - used in script 06)
--    We create them here so grants can reference them throughout.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ADV_EDU_ENGINEER COMMENT = 'Builds & maintains the pipeline';
CREATE ROLE IF NOT EXISTS ADV_EDU_ANALYST  COMMENT = 'Ministry analyst - reads all institutions';
CREATE ROLE IF NOT EXISTS ADV_EDU_INSTITUTION COMMENT = 'Institution user - sees only their own rows';
CREATE ROLE IF NOT EXISTS ADV_EDU_AUDITOR  COMMENT = 'Read-only incl. audit history';
 
-- ---------------------------------------------------------------------
-- 5. GRANTS  (wire roles to objects)
--    Engineer can do everything in the database.
--    Analyst / Institution / Auditor get read access to STAR only
--    (refined further in 06_governance.sql).
-- ---------------------------------------------------------------------
-- Database + warehouse usage
GRANT USAGE ON DATABASE ADV_EDU TO ROLE ADV_EDU_ENGINEER;
GRANT USAGE ON DATABASE ADV_EDU TO ROLE ADV_EDU_ANALYST;
GRANT USAGE ON DATABASE ADV_EDU TO ROLE ADV_EDU_INSTITUTION;
GRANT USAGE ON DATABASE ADV_EDU TO ROLE ADV_EDU_AUDITOR;
 
GRANT USAGE ON WAREHOUSE LOAD_WH      TO ROLE ADV_EDU_ENGINEER;
GRANT USAGE ON WAREHOUSE TRANSFORM_WH TO ROLE ADV_EDU_ENGINEER;
GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE ADV_EDU_ENGINEER;
GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE ADV_EDU_ANALYST;
GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE ADV_EDU_INSTITUTION;
GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE ADV_EDU_AUDITOR;
 
-- Engineer owns the build: full rights on all three schemas
GRANT ALL ON SCHEMA RAW    TO ROLE ADV_EDU_ENGINEER;
GRANT ALL ON SCHEMA SILVER TO ROLE ADV_EDU_ENGINEER;
GRANT ALL ON SCHEMA STAR   TO ROLE ADV_EDU_ENGINEER;
 
-- Reader roles: usage on STAR schema (table grants come in script 06)
GRANT USAGE ON SCHEMA STAR TO ROLE ADV_EDU_ANALYST;
GRANT USAGE ON SCHEMA STAR TO ROLE ADV_EDU_INSTITUTION;
GRANT USAGE ON SCHEMA STAR TO ROLE ADV_EDU_AUDITOR;

-- SELECT CURRENT_USER(); 

-- ---------------------------------------------------------------------
-- 6. ASSIGN ROLES TO YOUR USER so you can switch between them in demo
--    Replace the placeholder with your Snowflake login name.
-- ---------------------------------------------------------------------
GRANT ROLE ADV_EDU_ENGINEER    TO USER YOGIVIRAT21;
GRANT ROLE ADV_EDU_ANALYST     TO USER YOGIVIRAT21;
GRANT ROLE ADV_EDU_INSTITUTION TO USER YOGIVIRAT21;
GRANT ROLE ADV_EDU_AUDITOR     TO USER YOGIVIRAT21;
 
-- Done. Confirm objects exist:
SHOW WAREHOUSES LIKE '%_WH';
SHOW SCHEMAS IN DATABASE ADV_EDU;
