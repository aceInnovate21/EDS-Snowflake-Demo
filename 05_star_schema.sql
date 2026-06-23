-- =====================================================================
-- 05_star_schema.sql
-- Purpose : Build the dimensional model in the STAR schema.
--           Dimensions : INSTITUTION, PROGRAM, DATE, FUNDING_TYPE
--           Facts       : APPLICATIONS, DISBURSEMENTS, ENROLLMENTS
-- Run as  : ADV_EDU_ENGINEER
-- =====================================================================
USE ROLE ADV_EDU_ENGINEER;
USE DATABASE ADV_EDU;
USE SCHEMA STAR;
USE WAREHOUSE TRANSFORM_WH;
 
-- =====================================================================
-- DIMENSION : INSTITUTION
-- =====================================================================
CREATE OR REPLACE TABLE STAR.DIM_INSTITUTION AS
SELECT
  ROW_NUMBER() OVER (ORDER BY institution_id) AS institution_key,  -- surrogate
  institution_id,
  institution_name,
  institution_type,
  region,
  size_category
FROM SILVER.INSTITUTIONS;
 
-- =====================================================================
-- DIMENSION : PROGRAM  (distinct programs seen across applications)
-- =====================================================================
CREATE OR REPLACE TABLE STAR.DIM_PROGRAM AS
SELECT
  ROW_NUMBER() OVER (ORDER BY program_code) AS program_key,
  program_code,
  MAX(program_name) AS program_name
FROM SILVER.APPLICATIONS
WHERE program_code IS NOT NULL
GROUP BY program_code;
 
-- =====================================================================
-- DIMENSION : FUNDING_TYPE  (small reference dimension, defined inline)
-- =====================================================================
CREATE OR REPLACE TABLE STAR.DIM_FUNDING_TYPE AS
SELECT * FROM VALUES
  (1,'FT-OPS','Operating Grant','Base Funding'),
  (2,'FT-CAP','Capital Grant','Infrastructure'),
  (3,'FT-RES','Research Grant','Targeted'),
  (4,'FT-ACC','Access & Equity Grant','Targeted'),
  (5,'FT-INN','Innovation Grant','Targeted')
AS t(funding_type_key, funding_type_code, funding_type_name, funding_stream);
 
-- =====================================================================
-- DIMENSION : DATE  (fiscal-year grain is enough for this analysis)
--   Alberta fiscal year runs Apr 1 -> Mar 31.
-- =====================================================================
CREATE OR REPLACE TABLE STAR.DIM_DATE AS
SELECT
  ROW_NUMBER() OVER (ORDER BY fy) AS date_key,
  fy                              AS fiscal_year,
  'FY' || fy                      AS fiscal_year_label,
  (fy || '-04-01')::DATE          AS fiscal_year_start,
  ((fy::INT + 1) || '-03-31')::DATE AS fiscal_year_end
FROM (SELECT DISTINCT fiscal_year AS fy FROM SILVER.APPLICATIONS WHERE fiscal_year IS NOT NULL);
 
-- =====================================================================
-- FACT : APPLICATIONS  (grain = one approved/var application record)
-- =====================================================================
CREATE OR REPLACE TABLE STAR.FACT_APPLICATIONS AS
SELECT
  a.application_id,
  di.institution_key,
  dp.program_key,
  dd.date_key,
  dft.funding_type_key,
  a.amount_requested,
  a.status,
  a.submission_date
FROM SILVER.APPLICATIONS a
LEFT JOIN STAR.DIM_INSTITUTION  di ON a.institution_id    = di.institution_id
LEFT JOIN STAR.DIM_PROGRAM      dp ON a.program_code       = dp.program_code
LEFT JOIN STAR.DIM_DATE         dd ON a.fiscal_year        = dd.fiscal_year
LEFT JOIN STAR.DIM_FUNDING_TYPE dft ON a.funding_type_code = dft.funding_type_code;
 
-- =====================================================================
-- FACT : DISBURSEMENTS  (grain = one payment)
--   We keep the orphan_flag so analysts can see untraceable payments.
-- =====================================================================
CREATE OR REPLACE TABLE STAR.FACT_DISBURSEMENTS AS
SELECT
  d.disbursement_id,
  d.application_id,
  di.institution_key,
  dd.date_key,
  d.disbursed_amount,
  d.disbursement_date,
  d.orphan_flag
FROM SILVER.DISBURSEMENTS d
LEFT JOIN STAR.DIM_INSTITUTION di ON d.institution_id = di.institution_id
LEFT JOIN STAR.DIM_DATE        dd ON d.fiscal_year    = dd.fiscal_year;
 
-- =====================================================================
-- FACT : ENROLLMENTS  (grain = institution x program x fiscal year)
-- =====================================================================
CREATE OR REPLACE TABLE STAR.FACT_ENROLLMENTS AS
SELECT
  e.enrollment_id,
  di.institution_key,
  dp.program_key,
  dd.date_key,
  e.headcount,
  e.headcount_missing_flag
FROM SILVER.ENROLLMENTS e
LEFT JOIN STAR.DIM_INSTITUTION di ON e.institution_id = di.institution_id
LEFT JOIN STAR.DIM_PROGRAM     dp ON e.program_code   = dp.program_code
LEFT JOIN STAR.DIM_DATE        dd ON e.fiscal_year    = dd.fiscal_year;
 
-- =====================================================================
-- SANITY CHECKS
-- =====================================================================
SELECT 'dim_institution' t, COUNT(*) n FROM STAR.DIM_INSTITUTION
UNION ALL SELECT 'fact_applications',  COUNT(*) FROM STAR.FACT_APPLICATIONS
UNION ALL SELECT 'fact_disbursements', COUNT(*) FROM STAR.FACT_DISBURSEMENTS
UNION ALL SELECT 'fact_enrollments',   COUNT(*) FROM STAR.FACT_ENROLLMENTS;
