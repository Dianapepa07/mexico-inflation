"""
migrate_to_mongo.py
-------------------
Migrates the MySQL database 'mexico_inflation' to MongoDB in THREE parts:

  1) 1-to-1 migration: every MySQL table -> one MongoDB collection
     (it calls the getAll<Table> stored procedures, as in the migrateDatabases_v2.py template).
  2) NoSQL structure: one collection 'inflation_by_period' with ONE document per month,
     with all the indicators nested inside (so the dashboard reads everything with one query).
  3) Validation: compares row counts and the sum of 'value_pct' between MySQL and MongoDB.

Order of use: run it AFTER SQL scripts 01 to 06 and after load_data.py.
Run it from the python/ folder:   python migrate_to_mongo.py
"""
import json
import sys
from datetime import date, datetime, time
from decimal import Decimal

import pymysql
from pymongo import MongoClient, ASCENDING
from pymongo.errors import PyMongoError

from config import MYSQL_CONFIG, MONGO_URI, MONGO_DB_NAME

# ------------------------------------------------------------------
# CONNECTIONS
# ------------------------------------------------------------------
try:
    mysql_conn = pymysql.connect(**MYSQL_CONFIG)
except pymysql.MySQLError as e:
    print(f"ERROR: could not connect to MySQL (does the database '{MYSQL_CONFIG['database']}' exist?): {e}")
    sys.exit(1)

try:
    mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=4000)
    mongo_client.admin.command("ping")           # checks that MongoDB is running
except PyMongoError as e:
    print(f"ERROR: could not connect to MongoDB (is the service started?): {e}")
    sys.exit(1)

# MongoDB creates the database automatically when the first document is inserted,
# so it does NOT need to exist beforehand.
mongo_db = mongo_client[MONGO_DB_NAME]

TABLES = ["role", "app_user", "indicator", "variation_type",
          "series", "period", "observation", "audit_log"]


# ------------------------------------------------------------------
# HELPERS: MongoDB does not understand Decimal or date, so we convert them
# ------------------------------------------------------------------
def convert(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return datetime.combine(value, time.min)
    return value


def clean_row(row):
    doc = {k: convert(v) for k, v in row.items()}
    for field in ("old_data", "new_data"):       # JSON columns of 'audit_log'
        if isinstance(doc.get(field), str):
            doc[field] = json.loads(doc[field])
    return doc


# PART 1: table -> collection migration
def migrate_table(table_name, use_sp=True):
    try:
        with mysql_conn.cursor(pymysql.cursors.DictCursor) as cursor:
            if use_sp:
                cursor.callproc(f"getAll{table_name.capitalize()}")   # e.g. getAllObservation
            else:
                cursor.execute(f"SELECT * FROM `{table_name}`")
            rows = cursor.fetchall()

        mongo_db[table_name].drop()                 # avoids duplicates if the script runs twice
        if not rows:
            print(f"- Table '{table_name}' has no data (empty collection).")
            return
        mongo_db[table_name].insert_many([clean_row(r) for r in rows])
        print(f"OK Migration successful for '{table_name}' ({len(rows)} rows).")
    except Exception as e:
        print(f"ERROR migrating '{table_name}': {e}")


# PART 2: NoSQL structure (one document per month)
VARIATION_KEY = {"Monthly": "monthly", "Year to date": "ytd", "Annual": "annual"}


def build_period_documents():
    with mysql_conn.cursor(pymysql.cursors.DictCursor) as cursor:
        cursor.execute("SELECT period_year, period_month, period_date, indicator, variation_type, value_pct "
                       "FROM vw_inflation_detail ORDER BY period_date")
        rows = cursor.fetchall()

    docs = {}
    for r in rows:
        doc = docs.setdefault((r["period_year"], r["period_month"]), {
            "year": r["period_year"], "month": r["period_month"],
            "date": convert(r["period_date"]), "indicators": {}})
        doc["indicators"].setdefault(r["indicator"], {})[VARIATION_KEY[r["variation_type"]]] = float(r["value_pct"])

    collection = mongo_db["inflation_by_period"]
    collection.drop()
    collection.insert_many(list(docs.values()))
    collection.create_index([("year", ASCENDING), ("month", ASCENDING)], unique=True)
    mongo_db["observation"].create_index([("series_id", ASCENDING), ("period_id", ASCENDING)], unique=True)
    print(f"OK Collection 'inflation_by_period' created ({len(docs)} documents, one per month).")


# PART 3: MySQL vs MongoDB validation
def validate():
    print("\n=== VALIDATION MySQL vs MongoDB ===")
    all_ok = True
    with mysql_conn.cursor() as cursor:
        for table in TABLES:
            cursor.execute(f"SELECT COUNT(*) FROM `{table}`")
            sql_count = cursor.fetchone()[0]
            mongo_count = mongo_db[table].count_documents({})
            ok = sql_count == mongo_count
            all_ok &= ok
            print(f"{'OK  ' if ok else 'FAIL'} {table:<15} MySQL={sql_count:<5} MongoDB={mongo_count}")

        # Sum of all values: if it matches, the data arrived identical
        cursor.execute("SELECT SUM(value_pct) FROM observation")
        sql_sum = float(cursor.fetchone()[0] or 0)
        agg = list(mongo_db["observation"].aggregate([{"$group": {"_id": None, "s": {"$sum": "$value_pct"}}}]))
        mongo_sum = agg[0]["s"] if agg else 0.0
        ok = abs(sql_sum - mongo_sum) < 1e-6
        all_ok &= ok
        print(f"{'OK  ' if ok else 'FAIL'} SUM(value_pct)  MySQL={sql_sum:.6f} MongoDB={mongo_sum:.6f}")

        # Period documents = months that have observations
        cursor.execute("SELECT COUNT(DISTINCT period_id) FROM observation")
        sql_count = cursor.fetchone()[0]
        mongo_count = mongo_db["inflation_by_period"].count_documents({})
        ok = sql_count == mongo_count
        all_ok &= ok
        print(f"{'OK  ' if ok else 'FAIL'} inflation_by_period  months with data MySQL={sql_count} MongoDB={mongo_count}")

    print("\nMIGRATION VALIDATED: the data matches." if all_ok
          else "\nWARNING: there are differences, check the FAIL lines above.")


if __name__ == "__main__":
    print(f"Tables to migrate: {TABLES}\n")
    for table in TABLES:
        migrate_table(table, use_sp=True)
    build_period_documents()
    validate()

    mysql_conn.close()
    mongo_client.close()
