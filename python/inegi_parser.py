"""
inegi_parser.py
---------------
Reads the "Monthly inflation" CSV downloaded from INEGI's Economic Information Bank
(Banco de Información Económica) and turns it into Python lists ready to be
inserted into MySQL.

The INEGI CSV is NOT a simple table: it has ~12 header rows (title, available
period, base, etc.) followed by one row per month, with one column per series.
This module "unpacks" that layout.
"""
import csv
import re
import unicodedata
from datetime import date
from decimal import Decimal

# The CSV is in Spanish, so month abbreviations are Spanish (Ene = Jan, Abr = Apr, Ago = Aug, Dic = Dec)
MONTHS = {"Ene": 1, "Feb": 2, "Mar": 3, "Abr": 4, "May": 5, "Jun": 6,
          "Jul": 7, "Ago": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dic": 12}

PERIOD_PATTERN = re.compile(r"^[A-Za-z]{3} \d{4}$")   # example: "Ene 2025"
NUMBER_PATTERN = re.compile(r"^-?\d+(\.\d+)?$")        # example: "-0.210000000000"


def _strip_accents(text):
    """Lowercase and remove accents, to compare texts without encoding problems."""
    nfd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfd if unicodedata.category(c) != "Mn").lower().strip()


def _text_to_date(text):
    """'Ene 2025' -> date(2025, 1, 1)"""
    month, year = text.strip().split()
    return date(int(year), MONTHS[month], 1)


def _normalize_indicator(text):
    """Maps INEGI's Spanish indicator names to the English names used in the database."""
    t = _strip_accents(text)
    if "no subyacente" in t:
        return "Non-core"
    if "subyacente" in t:
        return "Core"
    if "consumo minimo" in t:
        return "Minimum consumption basket"
    if "canasta basica" in t:
        return "Basic basket"
    if "inpp" in t:
        return "PPI goods excl. oil"
    if "inpc" in t or "precios al consumidor" in t:
        return "Headline CPI"
    raise ValueError(f"Unrecognized indicator: {text}")


def _normalize_variation(text):
    t = _strip_accents(text)
    if "acumul" in t:
        return "Year to date"
    if "anual" in t:
        return "Annual"
    if "mensual" in t:
        return "Monthly"
    raise ValueError(f"Unrecognized variation type: {text}")


def read_inegi_csv(path):
    """
    Returns (series, observations, skipped):
      series       -> list of dicts: series_id, indicator, variation_type, available_from, available_to, base
      observations -> list of dicts: series_id, date (date), value (Decimal)
      skipped      -> list of (date, series_id, text) for NON-numeric values, for example
                      "N/E" (INEGI uses it when the data does not exist). They are not stored.
    """
    # INEGI files come in Latin-1 encoding (that is why 'latin-1' and not 'utf-8')
    with open(path, encoding="latin-1", newline="") as f:
        rows = list(csv.reader(f))

    # Locate each header row by its label (column 0)
    labels = {_strip_accents(row[0]): i for i, row in enumerate(rows) if row}
    title_row = rows[labels["titulo"]]
    period_row = rows[labels["periodo disponible"]]
    base_row = rows[labels["base"]]
    ids_index = labels["fecha"]            # the "Fecha" row holds the id of each series
    ids_row = rows[ids_index]

    # ---- 1) Series (one per column) ----
    series, columns = [], {}
    for j in range(1, len(ids_row)):
        if not ids_row[j].strip():
            continue
        parts = [p.strip() for p in title_row[j].split(",")]
        start, end = period_row[j].split("-")
        series.append({
            "series_id": int(ids_row[j]),
            "indicator": _normalize_indicator(parts[-2]),
            "variation_type": _normalize_variation(parts[-1]),
            "available_from": _text_to_date(start),
            "available_to": _text_to_date(end),
            "base": base_row[j].strip(),
        })
        columns[j] = int(ids_row[j])

    # ---- 2) Observations (one per month and per series) ----
    observations, skipped = [], []
    for row in rows[ids_index + 1:]:
        if not row or not PERIOD_PATTERN.match(row[0].strip()):
            continue
        month_date = _text_to_date(row[0])
        for j, series_id in columns.items():
            text = row[j].strip() if j < len(row) else ""
            if not text:
                continue
            if NUMBER_PATTERN.match(text):
                observations.append({"series_id": series_id, "date": month_date,
                                     "value": Decimal(text)})
            else:
                skipped.append((month_date, series_id, text))
    return series, observations, skipped


if __name__ == "__main__":      # quick test:  python inegi_parser.py
    s, o, skipped = read_inegi_csv("../data/INP_INP20261125012813.CSV")
    print(f"{len(s)} series, {len(o)} valid observations, {len(skipped)} skipped {skipped}")
    for x in s:
        print(x["series_id"], "|", x["indicator"], "|", x["variation_type"], "|",
              x["available_from"], "->", x["available_to"])
