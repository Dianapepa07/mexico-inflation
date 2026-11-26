import pandas as pd
import streamlit as st
from pymongo import MongoClient

from config import MONGO_URI, MONGO_DB_NAME

st.set_page_config(page_title="Inflation in Mexico", page_icon="📈", layout="wide")

# MongoDB stores the variation types in lowercase (annual, monthly, ytd).
# The dashboard shows them with readable names.
VARIATION_NAMES = {
    "annual": "Annual",
    "monthly": "Monthly",
    "ytd": "Year to date",
    "year to date": "Year to date",
}


# ------------------------- data access (MongoDB) -------------------------
@st.cache_data(ttl=300)
def load_data():
    db = MongoClient(MONGO_URI)[MONGO_DB_NAME]
    rows = []
    for d in db["inflation_by_period"].find({}, {"_id": 0}).sort([("year", 1), ("month", 1)]):
        for indicator, types in d["indicators"].items():
            for variation, value in types.items():
                name = VARIATION_NAMES.get(str(variation).strip().lower(), variation)
                rows.append({"date": d["date"], "indicator": indicator, "type": name, "value": value})
    df = pd.DataFrame(rows)
    if not df.empty:
        df["date"] = pd.to_datetime(df["date"])
        df["value"] = pd.to_numeric(df["value"], errors="coerce")
    return df


@st.cache_data(ttl=60)
def load_audit():
    db = MongoClient(MONGO_URI)[MONGO_DB_NAME]
    return pd.DataFrame(list(db["audit_log"].find({}, {"_id": 0}).sort("audit_id", -1)))


def classify(value):
    """Same rule as the MySQL function fn_classify_inflation (Banxico target: 3% +/- 1)."""
    if value < 2:
        return "Below target"
    if value <= 4:
        return "Within target"
    if value <= 6:
        return "Elevated"
    return "High"


df = load_data()
if df.empty:
    st.error("There is no data in MongoDB. Run migrate_to_mongo.py first.")
    st.stop()

if "Annual" not in df["type"].unique():
    st.error(f"No 'Annual' records found. Variation types in MongoDB: {list(df['type'].unique())}")
    st.stop()

# ------------------------------- header --------------------------------
st.title("📈 Inflation in Mexico")
st.caption("Source: INEGI (CPI, base 2nd half of July 2018 = 100) · Database: MySQL → MongoDB")

indicators = sorted(df["indicator"].unique())
st.sidebar.header("Filters")
selection = st.sidebar.multiselect("Indicators", indicators,
                                   default=[i for i in ("Headline CPI", "Core", "Non-core") if i in indicators])
variation = st.sidebar.radio("Variation type", ["Annual", "Monthly", "Year to date"])

tab1, tab2, tab3, tab4, tab5 = st.tabs(
    ["Summary", "Trend", "Reports", "Purchasing power", "Audit log"])

# ---------------------------------- Summary ---------------------------------
with tab1:
    annual = df[df["type"] == "Annual"]
    latest = annual["date"].max()
    st.subheader(f"Annual inflation, {latest:%B %Y}")
    columns = st.columns(3)
    for col, name in zip(columns, ["Headline CPI", "Core", "Non-core"]):
        series = annual[annual["indicator"] == name].sort_values("date")
        if len(series) >= 2:
            current, previous = series.iloc[-1]["value"], series.iloc[-2]["value"]
            col.metric(name, f"{current:.2f} %", f"{current - previous:+.2f} pp vs previous month")
            col.caption(f"Classification: **{classify(current)}**")

# ---------------------------------- Trend -----------------------------------
with tab2:
    st.subheader(f"{variation} inflation (%)")
    data = df[(df["type"] == variation) & (df["indicator"].isin(selection))]
    if data.empty:
        st.info("Choose at least one indicator in the sidebar.")
    else:
        st.line_chart(data.pivot(index="date", columns="indicator", values="value"))
        st.dataframe(data.sort_values(["date", "indicator"], ascending=[False, True]),
                     hide_index=True)

# ---------------------------------- Reports ---------------------------------
with tab3:
    st.subheader("Report 1 · Annual inflation with classification")
    r1 = df[df["type"] == "Annual"].copy()
    r1["classification"] = r1["value"].apply(classify)
    st.dataframe(r1[r1["indicator"].isin(selection)].sort_values("date", ascending=False),
                 hide_index=True)

    st.subheader("Report 2 · Summary of monthly inflation per indicator")
    r2 = (df[df["type"] == "Monthly"].groupby("indicator")["value"]
          .agg(months="count", average="mean", minimum="min", maximum="max").round(3).reset_index())
    st.dataframe(r2, hide_index=True)

    st.subheader("Report 3 · Core vs. Non-core (annual)")
    r3 = (df[(df["type"] == "Annual") & df["indicator"].isin(["Core", "Non-core"])]
          .pivot(index="date", columns="indicator", values="value"))
    st.bar_chart(r3)

# ----------------------------- Purchasing power ----------------------------
with tab4:
    st.subheader("How much is the money from one year ago worth today?")
    amount = st.number_input("Amount from one year ago (MXN)", min_value=0.0, value=1000.0, step=100.0)
    cpi = df[(df["indicator"] == "Headline CPI") & (df["type"] == "Annual")].sort_values("date").iloc[-1]
    real = amount / (1 + cpi["value"] / 100)
    st.metric("Current purchasing power", f"$ {real:,.2f}", f"{real - amount:,.2f} MXN")
    st.caption(f"Using the annual inflation of {cpi['date']:%B %Y}: {cpi['value']:.2f} %")

# -------------------------------- Audit log ---------------------------------
with tab5:
    st.subheader("Change log (generated by triggers in MySQL)")
    audit = load_audit()
    if audit.empty:
        st.info("There are no records yet. Do an INSERT/UPDATE/DELETE in MySQL and migrate again.")
    else:
        st.dataframe(audit.astype(str), hide_index=True)
