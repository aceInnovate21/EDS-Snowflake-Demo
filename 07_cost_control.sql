-- =====================================================================
-- 07_cost_control.sql  --  PART 1 : ACCOUNT-LEVEL RESOURCE MONITOR
-- Purpose : One ceiling for the entire account. Alerts on the way up;
--           suspends warehouses at the limit so spend cannot run away.
-- Run as  : ACCOUNTADMIN  (resource monitors are account objects)
-- Run after: 01_setup.sql
-- Safe to re-run : YES (CREATE OR REPLACE)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- ---------------------------------------------------------------------
-- ACCOUNT MONITOR
--   CREDIT_QUOTA          : credits allowed per FREQUENCY window.
--   FREQUENCY = MONTHLY   : the quota resets each month.
--   START_TIMESTAMP       : when tracking begins (now).
--   TRIGGERS              : actions at % of quota:
--     NOTIFY  -> sends an alert (no stop)
--     SUSPEND -> suspends warehouses after running queries finish
--     SUSPEND_IMMEDIATE -> kills running queries too (hard stop)
-- ---------------------------------------------------------------------
CREATE OR REPLACE RESOURCE MONITOR ADV_EDU_ACCOUNT_MONITOR
  WITH
    CREDIT_QUOTA  = 50                 -- <<MONTHLY_CREDIT_QUOTA>> keep small on a trial
    FREQUENCY     = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 60  PERCENT DO NOTIFY                 -- early heads-up
    ON 80  PERCENT DO NOTIFY                 -- getting close
    ON 95  PERCENT DO SUSPEND                -- stop new work, let queries finish
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;     -- hard stop, kill running queries
 
-- Attach the monitor to the ACCOUNT (covers every warehouse) ---------
ALTER ACCOUNT SET RESOURCE_MONITOR = ADV_EDU_ACCOUNT_MONITOR;
 
-- Confirm it exists and is attached:
SHOW RESOURCE MONITORS;
-- =====================================================================
-- 07_cost_control.sql  --  PART 2 : PER-WAREHOUSE MONITORS
-- Purpose : A small credit ceiling on each warehouse independently.
-- Run as  : ACCOUNTADMIN
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- LOAD_WH : ingestion. Light work, small quota. ----------------------
CREATE OR REPLACE RESOURCE MONITOR RM_LOAD_WH
  WITH CREDIT_QUOTA = 10 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75  PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE LOAD_WH SET RESOURCE_MONITOR = RM_LOAD_WH;
 
-- TRANSFORM_WH : ELT + star build. The heaviest, slightly larger quota.
CREATE OR REPLACE RESOURCE MONITOR RM_TRANSFORM_WH
  WITH CREDIT_QUOTA = 20 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75  PERCENT DO NOTIFY
    ON 90  PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE TRANSFORM_WH SET RESOURCE_MONITOR = RM_TRANSFORM_WH;
 
-- REPORTING_WH : dashboards & queries. Light, small quota. -----------
CREATE OR REPLACE RESOURCE MONITOR RM_REPORTING_WH
  WITH CREDIT_QUOTA = 10 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75  PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE REPORTING_WH SET RESOURCE_MONITOR = RM_REPORTING_WH;
 
-- Verify the wiring:
SHOW RESOURCE MONITORS;
-- =====================================================================
-- 07_cost_control.sql  --  PART 3 : AUTO-SUSPEND & RIGHT-SIZING
-- Purpose : Prevent waste in normal use (vs. monitors = emergency stop).
-- Run as  : ACCOUNTADMIN or ADV_EDU_ENGINEER (warehouse owner)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- AUTO_SUSPEND : seconds of idle before the warehouse sleeps.
--   Lower = less waste. 60s is a good demo default; the warehouse
--   wakes in ~1s when the next query runs (AUTO_RESUME = TRUE).
ALTER WAREHOUSE LOAD_WH      SET AUTO_SUSPEND = 60  AUTO_RESUME = TRUE;
ALTER WAREHOUSE TRANSFORM_WH SET AUTO_SUSPEND = 60  AUTO_RESUME = TRUE;
ALTER WAREHOUSE REPORTING_WH SET AUTO_SUSPEND = 60  AUTO_RESUME = TRUE;
 
-- RIGHT-SIZING : match size to the job. For this demo XSMALL/SMALL is
--   plenty. The point to make on stage: resizing is one line, instant,
--   no downtime - so you scale up only when a job truly needs it.
ALTER WAREHOUSE TRANSFORM_WH SET WAREHOUSE_SIZE = 'SMALL';   -- ELT
ALTER WAREHOUSE LOAD_WH      SET WAREHOUSE_SIZE = 'XSMALL';  -- ingestion
ALTER WAREHOUSE REPORTING_WH SET WAREHOUSE_SIZE = 'XSMALL';  -- queries
 
-- Belt-and-suspenders: explicitly suspend everything right now so
-- nothing is running while you talk through the rest of the deck.
ALTER WAREHOUSE LOAD_WH      SUSPEND;
ALTER WAREHOUSE TRANSFORM_WH SUSPEND;
ALTER WAREHOUSE REPORTING_WH SUSPEND;
-- (They auto-resume the instant you run the next query - no harm done.)
-- =====================================================================
-- 07_cost_control.sql  --  PART 4 : BUDGET  (optional, notify-only)
-- Purpose : A monthly spend target with email notification.
-- Run as  : ACCOUNTADMIN
-- Note    : Budgets NOTIFY only - they do not suspend. Use them WITH
--           the resource monitors above, not instead of them.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- Budgets live in a schema. Snowflake provides a built-in account
-- budget; you can also create custom ones. Here we set a spending
-- limit and a notification email on the account-level budget.
 
-- 1. Add your email as a notification recipient (verified contact).
--    Replace with the address you want alerts sent to.
CREATE OR REPLACE NOTIFICATION INTEGRATION ADV_EDU_BUDGET_NOTIFY
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<<YOUR_EMAIL>>');
 
-- 2. Configure the account budget: a monthly dollar/credit target and
--    the recipients to notify as you approach it. (Run in Snowsight:
--    Admin > Cost Management > Budgets is the UI equivalent.)
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET()
  !SET_SPENDING_LIMIT(50);                    -- credits/month target
 
CALL SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET()
  !SET_EMAIL_NOTIFICATIONS(
     'ADV_EDU_BUDGET_NOTIFY',                 -- the integration above
     '<<YOUR_EMAIL>>');
 
-- 3. Check the budget status:
SELECT SNOWFLAKE.LOCAL.ACCOUNT_ROOT_BUDGET()!GET_SPENDING_LIMIT();


-- =====================================================================
-- 07_cost_control.sql  --  PART 5 : USAGE & SPEND VISIBILITY
-- Purpose : See actual credit consumption. Read-only.
-- Run as  : ACCOUNTADMIN (ACCOUNT_USAGE needs privilege)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- 1. CREDITS PER WAREHOUSE, last 7 days -------------------------------
--    The headline number: what each warehouse actually cost.
SELECT
  warehouse_name,
  ROUND(SUM(credits_used), 3) AS credits_used,
  ROUND(SUM(credits_used) * <<DOLLARS_PER_CREDIT>>, 2) AS approx_usd
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits_used DESC;
--   <<DOLLARS_PER_CREDIT>> : your edition's credit price (e.g. ~3 for
--   Standard). On a trial you can leave this as 1 to just show credits.
 
-- 2. DAILY CREDIT TREND, last 14 days ---------------------------------
SELECT
  DATE_TRUNC('day', start_time) AS day,
  ROUND(SUM(credits_used), 3)   AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -14, CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 1;
 
-- 3. RESOURCE MONITOR STATUS  (how close to the quotas?) -------------
SHOW RESOURCE MONITORS;
--   Look at USED_CREDITS vs CREDIT_QUOTA and the PERCENT_USED column.
 
-- 4. MOST EXPENSIVE QUERIES, last 24h  (find waste) ------------------
--    INFORMATION_SCHEMA has no latency, good for a live look.
SELECT
  query_id,
  LEFT(query_text, 60) AS query_preview,
  warehouse_name,
  ROUND(total_elapsed_time/1000, 1) AS seconds,
  execution_status
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
        DATEADD('hour', -24, CURRENT_TIMESTAMP()),
        CURRENT_TIMESTAMP()))
ORDER BY total_elapsed_time DESC
LIMIT 10;
 
-- 5. STORAGE used by the demo database (storage is cheap & flat) -----
SELECT
  table_schema,
  ROUND(SUM(active_bytes)/1024/1024, 2) AS mb_used
FROM ADV_EDU.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
GROUP BY 1 ORDER BY mb_used DESC;


-- =====================================================================
-- 07_cost_control.sql  --  PART 6 : RESET (optional)
-- Purpose : Detach and drop the cost-control objects cleanly.
-- Run as  : ACCOUNTADMIN
-- =====================================================================
USE ROLE ACCOUNTADMIN;
 
-- Detach monitors from warehouses & account, then drop them ----------
ALTER WAREHOUSE LOAD_WH      UNSET RESOURCE_MONITOR;
ALTER WAREHOUSE TRANSFORM_WH UNSET RESOURCE_MONITOR;
ALTER WAREHOUSE REPORTING_WH UNSET RESOURCE_MONITOR;
ALTER ACCOUNT                UNSET RESOURCE_MONITOR;
 
DROP RESOURCE MONITOR IF EXISTS RM_LOAD_WH;
DROP RESOURCE MONITOR IF EXISTS RM_TRANSFORM_WH;
DROP RESOURCE MONITOR IF EXISTS RM_REPORTING_WH;
DROP RESOURCE MONITOR IF EXISTS ADV_EDU_ACCOUNT_MONITOR;
 
-- Remove the budget notification integration -------------------------
DROP INTEGRATION IF EXISTS ADV_EDU_BUDGET_NOTIFY;
 
-- Confirm everything is gone:
SHOW RESOURCE MONITORS;
