# ============================================================
# FILE: src/bronze/profiler.py
# PURPOSE: Profiles source data to understand its structure
#          and quality BEFORE writing any cleaning rules.
#          Generates key statistics per column and dataset.
#          Output drives all Silver layer design decisions.
# ============================================================

import pandas as pd
import json
import os
from datetime import datetime
from src.utils.logger import get_logger

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from config.config import EXPECTED_ROW_COUNTS, PRIMARY_KEYS

logger = get_logger(__name__)

REPORTS_DIR = r"D:\1_my_projects\HEALTHCARE PROVIDER FRAUD DETECTION ANALYSIS\python_pipeline\reports"


def profile_dataset(df, dataset_name):
    """
    Generate a profile report for one dataset.

    Checks:
    - Row count vs expected
    - Null counts per column
    - Blank string counts
    - 'NA' placeholder counts
    - Duplicate primary key count
    - Top 5 values per column

    Args:
        df:           pandas DataFrame
        dataset_name: name of the dataset

    Returns:
        dict: profiling results
    """
    logger.info(f"Profiling: {dataset_name}")

    # Exclude audit columns from profiling
    audit_cols = ["ingestion_timestamp", "source_file_name", "batch_id"]
    source_cols = [c for c in df.columns if c not in audit_cols]
    data = df[source_cols]

    # ── Row count ─────────────────────────────────────────────
    actual_rows   = len(data)
    expected_rows = EXPECTED_ROW_COUNTS.get(dataset_name, "Unknown")
    row_match     = actual_rows == expected_rows

    # ── Duplicates ────────────────────────────────────────────
    pk_cols     = PRIMARY_KEYS.get(dataset_name, [])
    pk_dups     = 0
    if pk_cols:
        pk_dups = int(data.duplicated(subset=pk_cols).sum())

    # ── Column stats ──────────────────────────────────────────
    column_stats = {}
    for col in source_cols:
        null_count  = int(data[col].isnull().sum())
        blank_count = int((data[col] == "").sum())
        na_count    = int((data[col] == "NA").sum())
        distinct    = int(data[col].nunique())
        top_values  = data[col].value_counts().head(5).to_dict()

        column_stats[col] = {
            "null_count":    null_count,
            "blank_count":   blank_count,
            "na_count":      na_count,
            "distinct_count": distinct,
            "top_5_values":  {str(k): int(v) for k, v in top_values.items()}
        }

    profile = {
        "dataset":        dataset_name,
        "profiled_at":    datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "row_count":      actual_rows,
        "expected_rows":  expected_rows,
        "row_count_match": row_match,
        "column_count":   len(source_cols),
        "pk_duplicates":  pk_dups,
        "columns":        column_stats
    }

    logger.info(f"  Rows: {actual_rows:,} | Expected: {expected_rows:,} | Match: {row_match}")
    logger.info(f"  PK Duplicates: {pk_dups}")

    return profile


def profile_all_datasets(dataframes):
    """
    Profile all source DataFrames.

    Args:
        dataframes: dict of {dataset_name: DataFrame}

    Returns:
        dict: {dataset_name: profile}
    """
    logger.info("=" * 50)
    logger.info("Profiling all datasets")
    logger.info("=" * 50)

    all_profiles = {}

    for dataset_name, df in dataframes.items():
        profile = profile_dataset(df, dataset_name)
        all_profiles[dataset_name] = profile

    # Save report to JSON file
    os.makedirs(REPORTS_DIR, exist_ok=True)
    report_path = os.path.join(
        REPORTS_DIR,
        f"profiling_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    )

    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(all_profiles, f, indent=2, default=str)

    logger.info(f"Profiling report saved: {report_path}")

    return all_profiles
