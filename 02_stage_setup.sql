-- =====================================================================
-- 02_ingestion.sql  --  SHARED SECTION  (run this first, always)
-- Purpose : CSV file format + RAW landing tables for all 5 datasets.
-- Run as  : ADV_EDU_ENGINEER (or ACCOUNTADMIN)
-- =====================================================================
USE ROLE ADV_EDU_ENGINEER;
USE DATABASE ADV_EDU;
USE SCHEMA RAW;
USE WAREHOUSE LOAD_WH;
 
-- ---------------------------------------------------------------------
-- CSV FILE FORMAT
--   SKIP_HEADER          = 1     -> first row is column names
--   FIELD_OPTIONALLY_ENCLOSED_BY = '"' -> handles "$1,250,000" text
--   NULL_IF              = ('','NULL') -> blank headcount becomes NULL
--   ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE -> tolerant of ragged rows
-- ---------------------------------------------------------------------
CREATE OR REPLACE FILE FORMAT RAW.CSV_FMT
  TYPE = 'CSV'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  COMMENT = 'Standard CSV format for all advanced-education files';
 
-- ---------------------------------------------------------------------
-- RAW LANDING TABLES
--   Every column is VARCHAR on purpose. The RAW layer accepts data
--   exactly as it arrives - including the messy bits. We fix types
--   and quality issues later, in 03_elt_silver.sql.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW.INSTITUTIONS (
  institution_id     VARCHAR,
  institution_name   VARCHAR,
  institution_type   VARCHAR,
  region             VARCHAR,
  size_category      VARCHAR
);
 
CREATE OR REPLACE TABLE RAW.APPLICATIONS (
  application_id     VARCHAR,
  institution_id     VARCHAR,
  institution_name   VARCHAR,   -- messy: multiple spellings
  program_code       VARCHAR,
  program_name       VARCHAR,
  funding_type_code  VARCHAR,
  fiscal_year        VARCHAR,
  amount_requested   VARCHAR,
  submission_date    VARCHAR,   -- messy: mixed date formats
  status             VARCHAR
);
 
CREATE OR REPLACE TABLE RAW.ENROLLMENTS (
  enrollment_id      VARCHAR,
  institution_id     VARCHAR,   -- messy: mismatched id format (I-002)
  program_code       VARCHAR,
  fiscal_year        VARCHAR,
  headcount          VARCHAR    -- messy: sometimes NULL
);
 
CREATE OR REPLACE TABLE RAW.FUNDING_DECISIONS (
  decision_id        VARCHAR,
  application_id     VARCHAR,
  institution_id     VARCHAR,
  funding_type_code  VARCHAR,
  fiscal_year        VARCHAR,
  approved_amount    VARCHAR,   -- messy: text "$1,250,000"
  decision_date      VARCHAR,
  decision           VARCHAR
);
 
CREATE OR REPLACE TABLE RAW.DISBURSEMENTS (
  disbursement_id    VARCHAR,
  application_id     VARCHAR,   -- messy: some orphan ids
  institution_id     VARCHAR,
  fiscal_year        VARCHAR,
  disbursed_amount   VARCHAR,
  disbursement_date  VARCHAR    -- messy: mixed date formats
);
