-- =====================================================================
-- 03_ingestion_PUT.sql  --  LOCAL UPLOAD (no AWS needed)
-- Purpose : Load the 5 CSVs from your laptop into the raw tables.
-- Prereq  : Stage, file format, and RAW tables already created
--           (in your stage setup script).
-- Run as  : ADV_EDU_ENGINEER
-- Note    : The PUT command runs in SnowSQL (CLI), NOT the web worksheet.
--           Everything else runs fine in a Snowsight worksheet.
-- =====================================================================
USE ROLE ADV_EDU_ENGINEER;
USE DATABASE ADV_EDU;
USE SCHEMA RAW;

CREATE OR REPLACE STAGE RAW.ADV_EDU_LOCAL_STAGE
  FILE_FORMAT = RAW.CSV_FMT
  COMMENT = 'Internal stage for local PUT uploads';
-- ---------------------------------------------------------------------
-- 1. PUT  ***RUN THESE IN SnowSQL, NOT THE WEB WORKSHEET***
--     Windows path example : file://C:\\data\\institutions.csv
--     Mac/Linux path example: file:///Users/you/data/institutions.csv
--     AUTO_COMPRESS gzips in transit -> files land as <name>.csv.gz
--     OVERWRITE=TRUE lets you re-run during rehearsal without errors
-- ---------------------------------------------------------------------
-- PUT file:///Users/yogesh/Desktop/ACE/Development/Snowflake/files/applications.csv      @RAW.ADV_EDU_LOCAL_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
-- PUT file:///Users/yogesh/Desktop/ACE/Development/Snowflake/files/disbursements.csv  @RAW.ADV_EDU_LOCAL_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
-- PUT file:///Users/yogesh/Desktop/ACE/Development/Snowflake/files/enrollments.csv   @RAW.ADV_EDU_LOCAL_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
-- PUT file:///Users/yogesh/Desktop/ACE/Development/Snowflake/files/funding_decisions.csv    @RAW.ADV_EDU_LOCAL_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;
-- PUT file://<<LOCAL_PATH>>/disbursements.csv       @RAW.ADV_EDU_LOCAL_STAGE AUTO_COMPRESS=TRUE OVERWRITE=TRUE;

-- Confirm the files are staged (works in worksheet too):
LIST @RAW.ADV_EDU_LOCAL_STAGE;

-- ---------------------------------------------------------------------
-- 2. COPY INTO  (load each staged file into its raw table)
--     ON_ERROR = 'CONTINUE' so one odd row never stops the demo.
-- ---------------------------------------------------------------------
COPY INTO RAW.INSTITUTIONS
  FROM @RAW.ADV_EDU_LOCAL_STAGE/institutions.csv.gz
  FILE_FORMAT = RAW.CSV_FMT ON_ERROR = 'CONTINUE';

COPY INTO RAW.APPLICATIONS
  FROM @RAW.ADV_EDU_LOCAL_STAGE/applications.csv.gz
  FILE_FORMAT = RAW.CSV_FMT ON_ERROR = 'CONTINUE';

COPY INTO RAW.ENROLLMENTS
  FROM @RAW.ADV_EDU_LOCAL_STAGE/enrollments.csv.gz
  FILE_FORMAT = RAW.CSV_FMT ON_ERROR = 'CONTINUE';

COPY INTO RAW.FUNDING_DECISIONS
  FROM @RAW.ADV_EDU_LOCAL_STAGE/funding_decisions.csv.gz
  FILE_FORMAT = RAW.CSV_FMT ON_ERROR = 'CONTINUE';

COPY INTO RAW.DISBURSEMENTS
  FROM @RAW.ADV_EDU_LOCAL_STAGE/disbursements.csv.gz
  FILE_FORMAT = RAW.CSV_FMT ON_ERROR = 'CONTINUE';

-- ---------------------------------------------------------------------
-- 3. VERIFY THE LOADS  (row counts + a peek at the mess)
-- ---------------------------------------------------------------------

SELECT * FROM RAW.INSTITUTIONS
SELECT * FROM RAW.APPLICATIONS
SELECT * FROM RAW.ENROLLMENTS
SELECT * FROM RAW.FUNDING_DECISIONS
SELECT * FROM RAW.DISBURSEMENTS;

SELECT 'institutions'      AS tbl, COUNT(*) AS row_count FROM RAW.INSTITUTIONS
UNION ALL SELECT 'applications',      COUNT(*) FROM RAW.APPLICATIONS
UNION ALL SELECT 'enrollments',       COUNT(*) FROM RAW.ENROLLMENTS
UNION ALL SELECT 'funding_decisions', COUNT(*) FROM RAW.FUNDING_DECISIONS
UNION ALL SELECT 'disbursements',     COUNT(*) FROM RAW.DISBURSEMENTS;





-- Show the data quality issues live (great demo moment):
SELECT DISTINCT institution_name FROM RAW.APPLICATIONS
  WHERE institution_name ILIKE '%plains%';            -- multiple spellings
SELECT submission_date FROM RAW.APPLICATIONS LIMIT 10;   -- mixed date formats
SELECT approved_amount FROM RAW.FUNDING_DECISIONS LIMIT 5; -- "$..." text
SELECT COUNT(*) FROM RAW.ENROLLMENTS WHERE headcount IS NULL; -- nulls