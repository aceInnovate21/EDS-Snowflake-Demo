-- =====================================================================
-- 06_governance.sql
-- Purpose : Governed access over the STAR schema.
--           RBAC grants, row-level security, dynamic masking, audit.
-- Run as  : ACCOUNTADMIN for policy creation; demo as the reader roles.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE DATABASE ADV_EDU;
USE SCHEMA STAR;
 
-- ---------------------------------------------------------------------
-- 1. TABLE-LEVEL GRANTS  (reader roles can SELECT the star schema)
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA STAR TO ROLE ADV_EDU_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA STAR TO ROLE ADV_EDU_INSTITUTION;
GRANT SELECT ON ALL TABLES IN SCHEMA STAR TO ROLE ADV_EDU_AUDITOR;
-- keep future tables covered too:
GRANT SELECT ON FUTURE TABLES IN SCHEMA STAR TO ROLE ADV_EDU_ANALYST;
 
-- ---------------------------------------------------------------------
-- 2. ROW-LEVEL SECURITY
--    Goal: an INSTITUTION user sees ONLY their own institution's rows,
--    while ANALYST and AUDITOR see everything.
--    We map a role to an institution via a small entitlement table.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE STAR.ROLE_INSTITUTION_MAP (
  role_name      VARCHAR,
  institution_id VARCHAR
);
-- Example entitlement: this institution role only sees INST-002.
-- Replace with the institution you want to demo.
INSERT INTO STAR.ROLE_INSTITUTION_MAP VALUES
  ('ADV_EDU_INSTITUTION', '<<DEMO_INSTITUTION_ID>>');
 
-- The row access policy: allow if privileged role, OR if the current
-- role is entitled to that institution_key.
CREATE OR REPLACE ROW ACCESS POLICY STAR.RAP_INSTITUTION
  AS (institution_key NUMBER) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ACCOUNTADMIN','ADV_EDU_ENGINEER','ADV_EDU_ANALYST','ADV_EDU_AUDITOR')
    OR EXISTS (
      SELECT 1
      FROM STAR.DIM_INSTITUTION di
      JOIN STAR.ROLE_INSTITUTION_MAP m
        ON di.institution_id = m.institution_id
      WHERE di.institution_key = institution_key
        AND m.role_name = CURRENT_ROLE()
    );
 
-- Attach the policy to the facts (column it keys on must exist in table)
ALTER TABLE STAR.FACT_APPLICATIONS
  ADD ROW ACCESS POLICY STAR.RAP_INSTITUTION ON (institution_key);
ALTER TABLE STAR.FACT_DISBURSEMENTS
  ADD ROW ACCESS POLICY STAR.RAP_INSTITUTION ON (institution_key);
ALTER TABLE STAR.FACT_ENROLLMENTS
  ADD ROW ACCESS POLICY STAR.RAP_INSTITUTION ON (institution_key);
 
-- ---------------------------------------------------------------------
-- 3. DYNAMIC DATA MASKING
--    Goal: hide small-cell enrollment counts (a privacy risk under FOIP)
--    from roles without clearance. Analyst & auditor see real numbers;
--    institution role sees masked values below a suppression threshold.
-- ---------------------------------------------------------------------
CREATE OR REPLACE MASKING POLICY STAR.MASK_SMALL_HEADCOUNT
  AS (val NUMBER) RETURNS NUMBER ->
    CASE
      WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','ADV_EDU_ENGINEER','ADV_EDU_ANALYST','ADV_EDU_AUDITOR')
        THEN val
      WHEN val < 10 THEN NULL          -- suppress small cells
      ELSE val
    END;
 
ALTER TABLE STAR.FACT_ENROLLMENTS
  MODIFY COLUMN headcount
  SET MASKING POLICY STAR.MASK_SMALL_HEADCOUNT;
 
-- ---------------------------------------------------------------------
-- 4. THE LIVE DEMO  (run these as you switch roles on stage)
-- ---------------------------------------------------------------------
-- As the ministry analyst: sees ALL institutions
USE ROLE ADV_EDU_ANALYST;
USE WAREHOUSE REPORTING_WH;
SELECT COUNT(*) AS rows_visible FROM STAR.FACT_APPLICATIONS;
 
-- As the institution user: sees ONLY their entitled institution
USE ROLE ADV_EDU_INSTITUTION;
SELECT COUNT(*) AS rows_visible FROM STAR.FACT_APPLICATIONS;
--   ^ same query, far fewer rows. Row-level security in action.
 
-- ---------------------------------------------------------------------
-- 5. AUDIT  (who queried what - answer the auditor's question)
--    ACCESS_HISTORY has ~ up to 3h latency; QUERY_HISTORY is immediate.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
SELECT query_text, user_name, role_name, start_time
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE query_text ILIKE '%FACT_APPLICATIONS%'
ORDER BY start_time DESC
LIMIT 20;
 
-- ---------------------------------------------------------------------
-- 6. TIME TRAVEL  (reproduce a report exactly as it was N hours ago)
--    Useful for audit defence: 'show me last quarter's numbers as run'.
-- ---------------------------------------------------------------------
SELECT COUNT(*) FROM STAR.FACT_APPLICATIONS AT(OFFSET => -3600);  -- 1h ago
 
-- ---------------------------------------------------------------------
-- 7. (Reset helper) remove policies if you want to re-run cleanly
-- ---------------------------------------------------------------------
-- ALTER TABLE STAR.FACT_APPLICATIONS  DROP ROW ACCESS POLICY STAR.RAP_INSTITUTION;
-- ALTER TABLE STAR.FACT_DISBURSEMENTS DROP ROW ACCESS POLICY STAR.RAP_INSTITUTION;
-- ALTER TABLE STAR.FACT_ENROLLMENTS   DROP ROW ACCESS POLICY STAR.RAP_INSTITUTION;
-- ALTER TABLE STAR.FACT_ENROLLMENTS   MODIFY COLUMN headcount UNSET MASKING POLICY;
