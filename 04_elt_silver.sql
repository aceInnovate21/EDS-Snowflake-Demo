-- =====================================================================
-- 04_elt_silver.sql
-- Purpose : Clean & conform RAW -> SILVER. Each fix maps to a problem
--           described in the first half of the session.
-- Run as  : ADV_EDU_ENGINEER
-- =====================================================================
USE ROLE ADV_EDU_ENGINEER;
USE DATABASE ADV_EDU;
USE SCHEMA SILVER;
USE WAREHOUSE TRANSFORM_WH;
 
-- ---------------------------------------------------------------------
-- HELPER : a robust date parser
--   Source systems sent dates in several formats:
--     2023-01-15   |   Jan 15 2023   |   15/01/2023   |   01/15/2023
--   TRY_TO_DATE returns NULL instead of erroring, so we try formats
--   in order with COALESCE and keep the first that succeeds.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION SILVER.PARSE_ANY_DATE(d VARCHAR)
RETURNS DATE
AS
$$
  COALESCE(
    TRY_TO_DATE(d, 'YYYY-MM-DD'),
    TRY_TO_DATE(d, 'MON DD YYYY'),
    TRY_TO_DATE(d, 'DD/MM/YYYY'),
    TRY_TO_DATE(d, 'MM/DD/YYYY')
  )
$$;
 
-- =====================================================================
-- 1. SILVER.INSTITUTIONS  (already clean - just type it properly)
--    This is our CONFORMED master: the source of truth for names & ids.
-- =====================================================================
CREATE OR REPLACE TABLE SILVER.INSTITUTIONS AS
SELECT
  TRIM(institution_id)        AS institution_id,
  TRIM(institution_name)      AS institution_name,
  TRIM(institution_type)      AS institution_type,
  TRIM(region)                AS region,
  TRIM(size_category)         AS size_category
FROM RAW.INSTITUTIONS;
 
-- =====================================================================
-- 2. SILVER.APPLICATIONS
--    Fixes:
--    (a) inconsistent institution_name  -> resolve to canonical id/name
--        by joining on the clean institution_id (which IS reliable here)
--    (b) mixed date formats             -> PARSE_ANY_DATE
--    (c) amount text -> number          -> TRY_TO_NUMBER
--    (d) duplicate rows                 -> ROW_NUMBER() de-duplication
-- =====================================================================
CREATE OR REPLACE TABLE SILVER.APPLICATIONS AS
WITH deduped AS (
  SELECT a.*,
         ROW_NUMBER() OVER (
           PARTITION BY application_id            -- a true duplicate shares its id
           ORDER BY submission_date
         ) AS rn
  FROM RAW.APPLICATIONS a
)
SELECT
  d.application_id,
  d.institution_id,
  i.institution_name              AS institution_name,   -- canonical, from master
  d.program_code,
  d.program_name,
  d.funding_type_code,
  d.fiscal_year,
  TRY_TO_NUMBER(d.amount_requested) AS amount_requested,
  SILVER.PARSE_ANY_DATE(d.submission_date) AS submission_date,
  INITCAP(d.status)               AS status
FROM deduped d
LEFT JOIN SILVER.INSTITUTIONS i
  ON d.institution_id = i.institution_id
WHERE d.rn = 1;                                          -- keep only first of each dup
 
-- =====================================================================
-- 3. SILVER.ENROLLMENTS
--    Fixes:
--    (a) mismatched institution_id (e.g. 'I-002' should be 'INST-002')
--        -> normalise the id format back to the master pattern
--    (b) NULL headcount -> flag it; do NOT invent a number
-- =====================================================================
CREATE OR REPLACE TABLE SILVER.ENROLLMENTS AS
SELECT
  enrollment_id,
  -- normalise 'I-002' -> 'INST-002' so it joins to the master
  CASE
    WHEN institution_id LIKE 'I-%'
      THEN 'INST-' || SUBSTR(institution_id, 3)
    ELSE institution_id
  END                                   AS institution_id,
  program_code,
  fiscal_year,
  TRY_TO_NUMBER(headcount)              AS headcount,
  (headcount IS NULL)                   AS headcount_missing_flag
FROM RAW.ENROLLMENTS;
 
-- =====================================================================
-- 4. SILVER.FUNDING_DECISIONS
--    Fix: approved_amount stored as text '$1,250,000'
--         -> strip $ and commas, cast to number
-- =====================================================================
CREATE OR REPLACE TABLE SILVER.FUNDING_DECISIONS AS
SELECT
  decision_id,
  application_id,
  institution_id,
  funding_type_code,
  fiscal_year,
  TRY_TO_NUMBER(
    REPLACE(REPLACE(approved_amount, '$', ''), ',', '')
  )                                     AS approved_amount,
  SILVER.PARSE_ANY_DATE(decision_date)  AS decision_date,
  INITCAP(decision)                     AS decision
FROM RAW.FUNDING_DECISIONS;
 
-- =====================================================================
-- 5. SILVER.DISBURSEMENTS
--    Fixes:
--    (a) mixed date formats -> PARSE_ANY_DATE
--    (b) orphan application_id -> flag rows whose application_id is not
--        present in SILVER.APPLICATIONS (don't silently drop money!)
-- =====================================================================
CREATE OR REPLACE TABLE SILVER.DISBURSEMENTS AS
SELECT
  dsb.disbursement_id,
  dsb.application_id,
  dsb.institution_id,
  dsb.fiscal_year,
  TRY_TO_NUMBER(dsb.disbursed_amount)        AS disbursed_amount,
  SILVER.PARSE_ANY_DATE(dsb.disbursement_date) AS disbursement_date,
  (app.application_id IS NULL)               AS orphan_flag  -- TRUE = no parent
FROM RAW.DISBURSEMENTS dsb
LEFT JOIN SILVER.APPLICATIONS app
  ON dsb.application_id = app.application_id;
 
-- =====================================================================
-- 6. DATA QUALITY REPORT  (quantify what we fixed - a strong demo beat)
-- =====================================================================
CREATE OR REPLACE VIEW SILVER.DATA_QUALITY_REPORT AS
SELECT 'applications: rows kept after dedupe' AS metric,
       COUNT(*)::VARCHAR AS value FROM SILVER.APPLICATIONS
UNION ALL
SELECT 'applications: raw rows (incl. dupes)',
       COUNT(*)::VARCHAR FROM RAW.APPLICATIONS
UNION ALL
SELECT 'enrollments: rows missing headcount',
       COUNT(*)::VARCHAR FROM SILVER.ENROLLMENTS WHERE headcount_missing_flag
UNION ALL
SELECT 'enrollments: institution ids normalised',
       COUNT(*)::VARCHAR FROM RAW.ENROLLMENTS WHERE institution_id LIKE 'I-%'
UNION ALL
SELECT 'disbursements: orphan rows flagged',
       COUNT(*)::VARCHAR FROM SILVER.DISBURSEMENTS WHERE orphan_flag;
 
-- View the report:
SELECT * FROM SILVER.DATA_QUALITY_REPORT;
