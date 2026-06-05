"""
notebooks/01_ingest.py
----------------------
Pulls Chicago Building Permit data from the City of Chicago
Data Portal (Socrata API) and saves to local CSV for analysis.

Data source: data.cityofchicago.org
Dataset ID:  ydr8-5enu (Building Permits)
No API key required for public datasets.
"""

import os
import time
import logging
import requests
import pandas as pd
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

BASE_URL = "https://data.cityofchicago.org/resource/ydr8-5enu.json"
OUTPUT_DIR = Path("data/raw")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

COLUMNS = [
    "id",
    "permit_type",
    "work_type",
    "issue_date",
    "estimated_cost",
    "community_area",
    "ward",
    "xcoordinate",
    "ycoordinate",
    "latitude",
    "longitude",
    "street_number",
    "street_direction",
    "street_name",
    "suffix",
]

def fetch_permits(start_year: int = 2019, end_year: int = 2024, batch_size: int = 50000) -> pd.DataFrame:
    """
    Fetch all building permits from Chicago Data Portal for the given year range.
    Uses pagination to handle large dataset (236,847 records).
    """
    all_records = []
    offset = 0

    date_filter = (
        f"issue_date >= '{start_year}-01-01T00:00:00' "
        f"AND issue_date <= '{end_year}-12-31T23:59:59'"
    )

    while True:
        params = {
            "$select": ", ".join(COLUMNS),
            "$where": date_filter,
            "$limit": batch_size,
            "$offset": offset,
            "$order": "issue_date ASC",
        }

        try:
            resp = requests.get(BASE_URL, params=params, timeout=60)
            resp.raise_for_status()
            batch = resp.json()
        except requests.RequestException as e:
            logger.error(f"API error at offset {offset}: {e}")
            break

        if not batch:
            logger.info(f"Pagination complete at offset {offset}.")
            break

        all_records.extend(batch)
        logger.info(f"Fetched {len(all_records):,} records so far...")
        offset += batch_size
        time.sleep(0.5)  # Rate limiting courtesy

    df = pd.DataFrame(all_records)
    logger.info(f"Total records fetched: {len(df):,}")
    return df


def clean_permits(df: pd.DataFrame) -> pd.DataFrame:
    """
    Clean and type-cast the raw permit DataFrame.
    Returns analysis-ready DataFrame.
    """
    df = df.copy()

    # Parse dates
    df["issue_date"] = pd.to_datetime(df["issue_date"], errors="coerce")

    # Parse numeric fields
    df["estimated_cost"] = pd.to_numeric(df["estimated_cost"], errors="coerce")
    df["ward"] = pd.to_numeric(df["ward"], errors="coerce")
    df["community_area"] = pd.to_numeric(df["community_area"], errors="coerce")
    df["latitude"] = pd.to_numeric(df["latitude"], errors="coerce")
    df["longitude"] = pd.to_numeric(df["longitude"], errors="coerce")

    # Standardize work type
    df["work_type"] = df["work_type"].str.upper().str.strip()

    # Derive year and month columns for easier SQL/groupby
    df["permit_year"] = df["issue_date"].dt.year
    df["permit_month"] = df["issue_date"].dt.to_period("M").astype(str)
    df["permit_quarter"] = df["issue_date"].dt.to_period("Q").astype(str)

    # Flag invalid cost values for transparency
    df["cost_flag"] = "normal"
    df.loc[df["estimated_cost"].isna(), "cost_flag"] = "missing"
    df.loc[df["estimated_cost"] <= 0, "cost_flag"] = "invalid"
    cost_p99 = df[df["estimated_cost"] > 0]["estimated_cost"].quantile(0.99)
    df.loc[df["estimated_cost"] > cost_p99, "cost_flag"] = "outlier"

    null_counts = df.isnull().sum()
    logger.info(f"Null counts per column:\n{null_counts[null_counts > 0]}")
    logger.info(f"Work type distribution:\n{df['work_type'].value_counts().head(10)}")
    logger.info(f"Year distribution:\n{df['permit_year'].value_counts().sort_index()}")

    return df


def run():
    logger.info("Starting Chicago permit data ingestion...")

    df_raw = fetch_permits(start_year=2019, end_year=2024)
    raw_path = OUTPUT_DIR / "permits_raw.csv"
    df_raw.to_csv(raw_path, index=False)
    logger.info(f"Raw data saved to {raw_path}")

    df_clean = clean_permits(df_raw)
    clean_path = OUTPUT_DIR / "permits_clean.csv"
    df_clean.to_csv(clean_path, index=False)
    logger.info(f"Clean data saved to {clean_path}")

    # Quick summary stats
    print("\n=== DATASET SUMMARY ===")
    print(f"Total permits: {len(df_clean):,}")
    print(f"Date range: {df_clean['issue_date'].min().date()} to {df_clean['issue_date'].max().date()}")
    print(f"Total estimated value: ${df_clean['estimated_cost'].sum() / 1e9:.2f}B")
    print(f"Unique community areas: {df_clean['community_area'].nunique()}")
    print(f"Unique wards: {df_clean['ward'].nunique()}")
    print(f"\nWork type breakdown:")
    print(df_clean["work_type"].value_counts().head(8).to_string())
    print(f"\nCost flags:")
    print(df_clean["cost_flag"].value_counts().to_string())

    return df_clean


if __name__ == "__main__":
    run()
