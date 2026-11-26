"""
load_data.py
------------
Reads the INEGI CSV and loads it into MySQL (tables: indicator, series, period, observation).
It can be run several times without duplicating data (it uses ON DUPLICATE KEY UPDATE).

Order of use:  1) 01_create_database_and_tables.sql   2) THIS SCRIPT   3) scripts 02 to 06
Run it from the python/ folder:   python load_data.py
"""
import sys
import pymysql
from config import MYSQL_CONFIG, CSV_PATH
from inegi_parser import read_inegi_csv

DESCRIPTIONS = {
    "Headline CPI": "National Consumer Price Index (INPC): measures the change in prices of the basket households consume",
    "Core": "Core inflation: excludes goods with very volatile prices (agricultural products, energy and government-set tariffs)",
    "Non-core": "Non-core inflation: agricultural products, energy and tariffs authorized by the government",
    "Minimum consumption basket": "Inflation of the minimum consumption basket of goods and services",
    "Basic basket": "Inflation of the basic basket of food and essential goods",
    "PPI goods excl. oil": "National Producer Price Index (INPP) for goods, excluding oil",
}


def main():
    # ---- 1) Read and "unpack" the CSV ----
    series, observations, skipped = read_inegi_csv(CSV_PATH)
    print(f"CSV read: {len(series)} series, {len(observations)} valid observations.")
    for day, series_id, text in skipped:
        print(f"  Warning - skipped: series {series_id}, {day:%b %Y} -> '{text}' (data not available at INEGI)")

    # ---- 2) Connect to MySQL ----
    try:
        conn = pymysql.connect(**MYSQL_CONFIG)
    except pymysql.MySQLError as e:
        print(f"ERROR: could not connect to MySQL: {e}")
        print("   Check config.py (user/password) and that you ran script 01 in Workbench.")
        sys.exit(1)

    try:
        with conn.cursor() as cur:
            # ---- 3) Indicators ----
            for name in dict.fromkeys(s["indicator"] for s in series):   # unique, in order
                cur.execute(
                    "INSERT INTO indicator (name, description) VALUES (%s, %s) "
                    "ON DUPLICATE KEY UPDATE description = VALUES(description)",
                    (name, DESCRIPTIONS.get(name)))
            cur.execute("SELECT name, indicator_id FROM indicator")
            indicator_ids = dict(cur.fetchall())

            cur.execute("SELECT name, variation_type_id FROM variation_type")
            variation_ids = dict(cur.fetchall())

            # ---- 4) Series ----
            for s in series:
                cur.execute(
                    "INSERT INTO series (series_id, indicator_id, variation_type_id, "
                    "available_from, available_to, base) VALUES (%s,%s,%s,%s,%s,%s) "
                    "ON DUPLICATE KEY UPDATE available_from = VALUES(available_from), "
                    "available_to = VALUES(available_to), base = VALUES(base)",
                    (s["series_id"], indicator_ids[s["indicator"]], variation_ids[s["variation_type"]],
                     s["available_from"], s["available_to"], s["base"]))

            # ---- 5) Periods (only the months that have data) ----
            months = sorted({(o["date"].year, o["date"].month) for o in observations})
            for year, month in months:
                cur.execute("INSERT INTO period (period_year, period_month) VALUES (%s, %s) "
                            "ON DUPLICATE KEY UPDATE period_year = period_year", (year, month))
            cur.execute("SELECT period_year, period_month, period_id FROM period")
            period_ids = {(y, m): i for y, m, i in cur.fetchall()}

            # ---- 6) Observations ----
            data = [(o["series_id"], period_ids[(o["date"].year, o["date"].month)], o["value"])
                    for o in observations]
            cur.executemany(
                "INSERT INTO observation (series_id, period_id, value_pct) VALUES (%s,%s,%s) "
                "ON DUPLICATE KEY UPDATE value_pct = VALUES(value_pct)", data)

        conn.commit()

        # ---- 7) Summary ----
        with conn.cursor() as cur:
            print("\nLoad completed. Rows per table:")
            for table in ("variation_type", "indicator", "series", "period", "observation"):
                cur.execute(f"SELECT COUNT(*) FROM `{table}`")
                print(f"   {table:<15} {cur.fetchone()[0]}")
    except Exception as e:
        conn.rollback()
        print(f"ERROR during the load (changes were rolled back): {e}")
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
