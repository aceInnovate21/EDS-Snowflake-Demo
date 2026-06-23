import streamlit as st
import altair as alt
from snowflake.snowpark.context import get_active_session

# ── Page setup ────────────────────────────────────────────────────────
st.set_page_config(page_title="Advanced Education — Funding Analytics", layout="wide")
session = get_active_session()

# GoA / Snowflake light-blue palette
NAVY, BLUE, SKY = "#0B2D4D", "#1789BD", "#29B5E8"

st.title("Advanced Education — Funding Analytics")
st.caption("Institutional funding equity, disbursement efficiency, and program trends")

# ── Load data from the three views ────────────────────────────────────
@st.cache_data(ttl=300)
def load(view):
    return session.table(f"ADV_EDU.STAR.{view}").to_pandas()

equity   = load("V_FUNDING_EQUITY")
lag      = load("V_DISBURSEMENT_LAG")
programs = load("V_PROGRAM_EFFICIENCY")

# ── Fiscal-year filter (applies to the first two reports) ─────────────
years = sorted(equity["FISCAL_YEAR"].dropna().unique())
sel = st.multiselect("Fiscal year", years, default=years)

eq = equity[equity["FISCAL_YEAR"].isin(sel)]
lg = lag[lag["FISCAL_YEAR"].isin(sel)]

# ── Headline metrics ──────────────────────────────────────────────────
c1, c2, c3 = st.columns(3)
c1.metric("Institutions funded", eq["INSTITUTION_NAME"].nunique())
c2.metric("Avg days to pay", f'{lg["AVG_DAYS_TO_PAY"].mean():.0f}' if len(lg) else "—")
review = (programs["FLAG"].str.startswith("Review")).sum()
c3.metric("Programs to review", int(review))

st.divider()

# ── Report 1: Funding Equity ──────────────────────────────────────────
st.subheader("1 · Funding equity — approved funding per enrolled student")
top_eq = eq.sort_values("FUNDING_PER_STUDENT", ascending=False).head(15)
chart1 = (
    alt.Chart(top_eq)
    .mark_bar(color=SKY)
    .encode(
        x=alt.X("FUNDING_PER_STUDENT:Q", title="Funding per student ($)"),
        y=alt.Y("INSTITUTION_NAME:N", sort="-x", title=None),
        tooltip=["INSTITUTION_NAME", "FISCAL_YEAR", "APPROVED_FUNDING",
                 "ENROLLED_STUDENTS", "FUNDING_PER_STUDENT"],
    )
    .properties(height=420)
)
st.altair_chart(chart1, use_container_width=True)
st.caption("Higher bars = more funding per student. Outliers may signal over- or under-funding relative to peers.")

st.divider()

# ── Report 2: Disbursement Lag ────────────────────────────────────────
st.subheader("2 · Disbursement lag — average days from application to payment")
top_lag = lg.sort_values("AVG_DAYS_TO_PAY", ascending=False).head(15)
chart2 = (
    alt.Chart(top_lag)
    .mark_bar(color=BLUE)
    .encode(
        x=alt.X("AVG_DAYS_TO_PAY:Q", title="Average days to pay"),
        y=alt.Y("INSTITUTION_NAME:N", sort="-x", title=None),
        tooltip=["INSTITUTION_NAME", "FISCAL_YEAR", "PAYMENTS",
                 "AVG_DAYS_TO_PAY", "TOTAL_DISBURSED"],
    )
    .properties(height=420)
)
st.altair_chart(chart2, use_container_width=True)
st.caption("Longer bars = slower payouts. Surfaces administrative bottlenecks between approval and disbursement.")

st.divider()

# ── Report 3: Program Efficiency ──────────────────────────────────────
st.subheader("3 · Program efficiency — enrollment trend vs. sustained funding")
def highlight(row):
    color = "#FBEFEA" if str(row["FLAG"]).startswith("Review") else ""
    return [f"background-color: {color}"] * len(row)

show = programs[["PROGRAM_NAME", "EARLIEST_STUDENTS", "LATEST_STUDENTS",
                 "ENROLLMENT_CHANGE", "APPROVED_FUNDING", "FLAG"]]
st.dataframe(show.style.apply(highlight, axis=1), use_container_width=True, hide_index=True)
st.caption("Rows flagged for review: declining enrollment while funding holds — candidates for reallocation.")