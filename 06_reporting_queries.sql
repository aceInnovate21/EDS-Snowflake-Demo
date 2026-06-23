-- =====================================================================
-- 06_reporting_queries.sql
-- Purpose : The three policy reports, built on the star schema.
-- Run as  : ADV_EDU_ANALYST (or ENGINEER)
-- =====================================================================
USE ROLE ADV_EDU_ANALYST;
USE DATABASE ADV_EDU;
USE SCHEMA STAR;
USE WAREHOUSE REPORTING_WH;
 
-- =====================================================================
-- REPORT 1 : FUNDING EQUITY
--   Question : Is funding proportional to enrollment across institutions?
--   Method   : approved $ per enrolled student, by institution & year.
--   A high $/student vs peers may indicate over-funding (or vice versa).
-- =====================================================================
WITH funding AS (
  SELECT di.institution_key, dd.fiscal_year,
         SUM(fa.amount_requested) AS requested
  FROM STAR.FACT_APPLICATIONS fa
  JOIN STAR.DIM_DATE dd ON fa.date_key = dd.date_key
  JOIN STAR.DIM_INSTITUTION di ON fa.institution_key = di.institution_key
  WHERE fa.status = 'Approved'
  GROUP BY 1,2
),
enrol AS (
  SELECT institution_key, dd.fiscal_year,
         SUM(headcount) AS students
  FROM STAR.FACT_ENROLLMENTS fe
  JOIN STAR.DIM_DATE dd ON fe.date_key = dd.date_key
  WHERE headcount IS NOT NULL
  GROUP BY 1,2
)
SELECT
  di.institution_name,
  di.region,
  f.fiscal_year,
  f.requested                              AS approved_funding,
  e.students                               AS enrolled_students,
  ROUND(f.requested / NULLIF(e.students,0), 0) AS funding_per_student
FROM funding f
JOIN enrol e
  ON f.institution_key = e.institution_key AND f.fiscal_year = e.fiscal_year
JOIN STAR.DIM_INSTITUTION di ON f.institution_key = di.institution_key
ORDER BY funding_per_student DESC;
 
-- =====================================================================
-- REPORT 2 : DISBURSEMENT LAG
--   Question : Are approved funds paid out on time?
--   Method   : days between application decision and disbursement.
--   Surfaces administrative bottlenecks.
-- =====================================================================
SELECT
  di.institution_name,
  dd.fiscal_year,
  COUNT(*)                                       AS payments,
  ROUND(AVG(DATEDIFF('day', a.submission_date, fd.disbursement_date)),1)
                                                 AS avg_days_to_pay,
  SUM(fd.disbursed_amount)                       AS total_disbursed
FROM STAR.FACT_DISBURSEMENTS fd
JOIN STAR.FACT_APPLICATIONS a ON fd.application_id = a.application_id
JOIN STAR.DIM_INSTITUTION di  ON fd.institution_key = di.institution_key
JOIN STAR.DIM_DATE dd         ON fd.date_key = dd.date_key
WHERE fd.orphan_flag = FALSE          -- exclude untraceable payments
GROUP BY 1,2
ORDER BY avg_days_to_pay DESC;
 
-- =====================================================================
-- REPORT 3 : PROGRAM EFFICIENCY
--   Question : Which programs decline in enrollment but keep funding?
--   Method   : compare earliest vs latest year enrollment per program,
--              alongside total approved funding. Declining + funded
--              = a reallocation candidate.
-- =====================================================================
WITH prog_year AS (
  SELECT dp.program_name, dd.fiscal_year, SUM(fe.headcount) AS students
  FROM STAR.FACT_ENROLLMENTS fe
  JOIN STAR.DIM_PROGRAM dp ON fe.program_key = dp.program_key
  JOIN STAR.DIM_DATE dd    ON fe.date_key = dd.date_key
  WHERE fe.headcount IS NOT NULL
  GROUP BY 1,2
),
trend AS (
  SELECT program_name,
         MIN_BY(students, fiscal_year) AS earliest_students,
         MAX_BY(students, fiscal_year) AS latest_students
  FROM prog_year
  GROUP BY 1
),
prog_funding AS (
  SELECT dp.program_name, SUM(fa.amount_requested) AS approved_funding
  FROM STAR.FACT_APPLICATIONS fa
  JOIN STAR.DIM_PROGRAM dp ON fa.program_key = dp.program_key
  WHERE fa.status = 'Approved'
  GROUP BY 1
)
SELECT
  t.program_name,
  t.earliest_students,
  t.latest_students,
  (t.latest_students - t.earliest_students) AS enrollment_change,
  pf.approved_funding,
  CASE WHEN t.latest_students < t.earliest_students
       THEN 'Review - declining enrollment, sustained funding'
       ELSE 'Stable / growing' END          AS flag
FROM trend t
JOIN prog_funding pf ON t.program_name = pf.program_name
ORDER BY enrollment_change ASC;


USE ROLE ADV_EDU_ENGINEER;
USE DATABASE ADV_EDU;
USE SCHEMA STAR;

-- View 1: Funding Equity
CREATE OR REPLACE VIEW STAR.V_FUNDING_EQUITY AS
WITH funding AS (
  SELECT di.institution_key, dd.fiscal_year,
         SUM(fa.amount_requested) AS requested
  FROM STAR.FACT_APPLICATIONS fa
  JOIN STAR.DIM_DATE dd ON fa.date_key = dd.date_key
  JOIN STAR.DIM_INSTITUTION di ON fa.institution_key = di.institution_key
  WHERE fa.status = 'Approved'
  GROUP BY 1,2
),
enrol AS (
  SELECT fe.institution_key, dd.fiscal_year,
         SUM(fe.headcount) AS students
  FROM STAR.FACT_ENROLLMENTS fe
  JOIN STAR.DIM_DATE dd ON fe.date_key = dd.date_key
  WHERE fe.headcount IS NOT NULL
  GROUP BY 1,2
)
SELECT di.institution_name, di.region, f.fiscal_year,
       f.requested AS approved_funding,
       e.students  AS enrolled_students,
       ROUND(f.requested / NULLIF(e.students,0), 0) AS funding_per_student
FROM funding f
JOIN enrol e ON f.institution_key = e.institution_key AND f.fiscal_year = e.fiscal_year
JOIN STAR.DIM_INSTITUTION di ON f.institution_key = di.institution_key
ORDER BY funding_per_student DESC;

-- View 2: Disbursement Lag
CREATE OR REPLACE VIEW STAR.V_DISBURSEMENT_LAG AS
SELECT di.institution_name, dd.fiscal_year,
       COUNT(*) AS payments,
       ROUND(AVG(DATEDIFF('day', a.submission_date, fd.disbursement_date)),1) AS avg_days_to_pay,
       SUM(fd.disbursed_amount) AS total_disbursed
FROM STAR.FACT_DISBURSEMENTS fd
JOIN STAR.FACT_APPLICATIONS a ON fd.application_id = a.application_id
JOIN STAR.DIM_INSTITUTION di  ON fd.institution_key = di.institution_key
JOIN STAR.DIM_DATE dd         ON fd.date_key = dd.date_key
WHERE fd.orphan_flag = FALSE
  AND DATEDIFF('day', a.submission_date, fd.disbursement_date) >= 0   -- only valid lags
GROUP BY 1,2
ORDER BY avg_days_to_pay DESC;

-- View 3: Program Efficiency
CREATE OR REPLACE VIEW STAR.V_PROGRAM_EFFICIENCY AS
WITH prog_year AS (
  SELECT dp.program_name, dd.fiscal_year, SUM(fe.headcount) AS students
  FROM STAR.FACT_ENROLLMENTS fe
  JOIN STAR.DIM_PROGRAM dp ON fe.program_key = dp.program_key
  JOIN STAR.DIM_DATE dd    ON fe.date_key = dd.date_key
  WHERE fe.headcount IS NOT NULL
  GROUP BY 1,2
),
trend AS (
  SELECT program_name,
         MIN_BY(students, fiscal_year) AS earliest_students,
         MAX_BY(students, fiscal_year) AS latest_students
  FROM prog_year GROUP BY 1
),
prog_funding AS (
  SELECT dp.program_name, SUM(fa.amount_requested) AS approved_funding
  FROM STAR.FACT_APPLICATIONS fa
  JOIN STAR.DIM_PROGRAM dp ON fa.program_key = dp.program_key
  WHERE fa.status = 'Approved'
  GROUP BY 1
)
SELECT t.program_name, t.earliest_students, t.latest_students,
       (t.latest_students - t.earliest_students) AS enrollment_change,
       pf.approved_funding,
       CASE WHEN t.latest_students < t.earliest_students
            THEN 'Review - declining enrollment, sustained funding'
            ELSE 'Stable / growing' END AS flag
FROM trend t
JOIN prog_funding pf ON t.program_name = pf.program_name
ORDER BY enrollment_change ASC;

GRANT SELECT ON ALL VIEWS IN SCHEMA STAR TO ROLE ADV_EDU_ANALYST;