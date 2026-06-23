# Snowflake for Real-World Data Workflows — A Public Sector Demo

**Edmonton Data Society — Snowflake Demo Presentation**

This repository contains the complete, runnable code for a 50-minute session on how Snowflake enables real-world data workflows, told from a public sector and consulting perspective. It walks a realistic dataset from raw, messy files all the way to a governed, decision-ready dashboard — the kind of journey data teams in government and beyond face every day.

The session pairs a story (the *why*) with a live demo (the *how*). Everything you need to reproduce the demo is here.

---

## The Scenario

A fictional but true-to-life project: the **Government of Alberta's Ministry of Advanced Education** funds 25 post-secondary institutions across the province. The data needed to answer one important policy question lives across several disconnected systems.

> **The policy question:** *Is post-secondary funding being allocated equitably and efficiently — and is the money actually reaching the institutions and students it was approved for?*

The demo turns five raw files into three decision-ready answers:

1. **Funding equity** — is funding proportional to enrollment across institutions?
2. **Disbursement efficiency** — are approved funds being paid out on time?
3. **Program efficiency** — which programs are declining in enrollment while funding holds steady?

All data is **synthetic**. The institution names, numbers, and findings are fictional and for demonstration only.

---

## The Architecture

```
Local CSVs ──► Internal Stage ──► RAW ──► SILVER (ELT) ──► STAR (model) ──► Reporting
   (PUT)         (Snowflake)      landing    cleansed       facts & dims     Snowsight
                                                                              + Streamlit
                          └──────────── Governance spans every layer ────────────┘
                              RBAC • row-level security • masking • audit
```

The pipeline follows a medallion pattern (RAW → SILVER → STAR) and loads data locally via `PUT` — **no cloud storage account required**.

---

## Repository Contents

| File | Purpose |
|------|---------|
| `01_setup.sql` | Creates the database, schemas (RAW / SILVER / STAR), virtual warehouses, roles, and grants. Run this first. |
| `02_stage_setup.sql` | Creates the CSV file format, the RAW landing tables, and the internal stage used for local uploads. |
| `03_ingestion.sql` | Loads the five CSVs from the internal stage into the RAW tables via `COPY INTO`, then verifies the loads. |
| `04_elt_silver.sql` | The heart of the demo: cleanses and conforms RAW into SILVER — standardizes institution names, parses mixed date formats, converts text amounts to numbers, removes duplicates, and flags records to reconcile. |
| `05_star_schema.sql` | Builds the dimensional model — `DIM_INSTITUTION`, `DIM_PROGRAM`, `DIM_DATE`, `DIM_FUNDING_TYPE`, and the `FACT_*` tables. |
| `06_governance.sql` | Role-based access control, row-level security, dynamic data masking, access history, and time travel. The live role-switch is the highlight of the demo. |
| `06_reporting_queries.sql` | The three policy queries, plus the reusable reporting views the dashboard reads from. |
| `07_cost_control.sql` | Resource monitors, spending limits, and usage queries — keeping a free-trial account safe and demonstrating predictable, governed spend. |
| `streamlit_app.py` | A Streamlit-in-Snowflake dashboard presenting the three policy reports. |

---

## The Datasets

Five CSV files, roughly 500 rows each, with realistic data quality conditions intentionally built in — so the cleansing step has something real to resolve.

| Dataset | Rows | Notable conditions to resolve |
|---------|------|-------------------------------|
| `institutions.csv` | 25 | Clean master reference (the source of truth). |
| `applications.csv` | ~640 | Institution names recorded several ways; mixed date formats; duplicate submissions. |
| `enrollments.csv` | ~500 | Missing headcounts; institution IDs in a non-standard format. |
| `funding_decisions.csv` | ~400 | Approved amounts stored as text (e.g. `"$1,250,000"`). |
| `disbursements.csv` | ~510 | Mixed date formats; a few payments referencing applications recorded elsewhere. |

> The CSV files themselves are not included in this repo. They are generated for the demo; reach out if you'd like a copy, or substitute your own data with the same column structure.

---

## How to Run

### Prerequisites

- A Snowflake account (a free trial is more than enough).
- [SnowSQL](https://docs.snowflake.com/en/user-guide/snowsql-install-config) installed locally — needed for the `PUT` command that uploads files from your machine. *(Alternatively, use the Snowsight "+ Files" upload button on the internal stage.)*
- The five CSV files saved in a known local folder.

### Steps

1. **Setup** — run `01_setup.sql` as `ACCOUNTADMIN`. Replace the `<<YOUR_SNOWFLAKE_USER>>` placeholder with your login so the demo roles are granted to you.
2. **Stage** — run `02_stage_setup.sql` to create the file format, RAW tables, and the internal stage.
3. **Upload & ingest** — from SnowSQL, `PUT` the CSVs into the internal stage, then run `03_ingestion.sql` to `COPY INTO` the RAW tables.
4. **Transform** — run `04_elt_silver.sql` to cleanse RAW into SILVER.
5. **Model** — run `05_star_schema.sql` to build the star schema.
6. **Govern** — run `06_governance.sql` to apply roles, row-level security, and masking.
7. **Report** — run `06_reporting_queries.sql` to create the views, then deploy `streamlit_app.py` as a Streamlit-in-Snowflake app.
8. **Cost control** *(recommended)* — run `07_cost_control.sql` to set spending guardrails.

### Placeholders to fill in

Search the scripts for `<<...>>` and replace with your own values:

- `<<YOUR_SNOWFLAKE_USER>>` — your Snowflake login username.
- `<<LOCAL_PATH>>` — the local folder containing the CSVs (used in the `PUT` command).
- `<<DEMO_INSTITUTION_ID>>` — the institution the restricted role is allowed to see (e.g. `INST-002`), for the governance demo.
- `<<YOUR_EMAIL>>` / `<<MONTHLY_CREDIT_QUOTA>>` — for cost-control notifications and limits.

---

## The Demo Flow (≈15 minutes)

1. **The raw material** — query RAW and see the data exactly as it arrives.
2. **Load** — upload locally with `PUT`, no cloud bucket required.
3. **Cleanse** — run the ELT and review the data-quality report.
4. **Model** — build the star schema.
5. **Govern** — *the highlight:* switch roles live and watch the same query return different data.
6. **Report** — open the dashboard and reveal the three policy answers.

---

## Notes

- **Data is synthetic.** All findings are illustrative, not real conclusions about any institution.
- **Local-first ingestion.** This demo deliberately avoids cloud storage so anyone can reproduce it on a free trial. The same pipeline works with an external stage and Snowpipe auto-ingest in production.
- **Governance is intentional.** The role-based access, masking, and audit features are the public-sector heart of this session — not an afterthought.

---

*Built for the Edmonton Data Society. Questions and contributions welcome.*
