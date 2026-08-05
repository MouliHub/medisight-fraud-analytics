# ============================================================
# FILE: src/bronze/validator.py
# PURPOSE: Validates source data quality before loading to SQL.
#          Runs checks on each DataFrame and raises an error
#          if any critical issue is found (fail-fast design).
#          Warnings are logged but don't stop the pipeline.
# ============================================================

import pandas as pd
import os
from src.utils.logger import get_logger

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from config.config import EXPECTED_ROW_COUNTS, NOT_NULL_COLUMNS, PRIMARY_KEYS

logger = get_logger(__name__)


def validate_dataset(df, dataset_name):
    """
    Run all validation checks on one dataset.

    Checks:
    1. Row count matches expected
    2. Critical columns have no nulls
    3. No duplicate primary keys
    4. Date columns contain valid dates
    5. Numeric columns have no negative values

    Args:
        df:           pandas DataFrame
        dataset_name: name of the dataset

    Returns:
        dict: validation summary with passed/failed counts

    Raises:
        Exception: if any CRITICAL check fails
    """
    logger.info(f"Validating: {dataset_name}")

    audit_cols  = ["ingestion_timestamp", "source_file_name", "batch_id"]
    data        = df[[c for c in df.columns if c not in audit_cols]]

    passed = 0
    failed = 0
    critical_failures = []

    # ── CHECK 1: Row Count ────────────────────────────────────
    expected = EXPECTED_ROW_COUNTS.get(dataset_name)
    actual   = len(data)
    if expected and actual != expected:
        msg = f"Row count mismatch: expected {expected:,}, got {actual:,}"
        logger.error(f"  [CRITICAL] {msg}")
        critical_failures.append(msg)
        failed += 1
    else:
        logger.info(f"  [PASS] Row count: {actual:,}")
        passed += 1

    # ── CHECK 2: Not Null on critical columns ─────────────────
    critical_cols = NOT_NULL_COLUMNS.get(dataset_name, [])
    for col in critical_cols:
        if col not in data.columns:
            continue
        null_count = data[col].isnull().sum()
        if null_count > 0:
            msg = f"NULL values in critical column '{col}': {null_count:,} rows"
            logger.error(f"  [CRITICAL] {msg}")
            critical_failures.append(msg)
            failed += 1
        else:
            logger.info(f"  [PASS] No nulls in '{col}'")
            passed += 1

    # ── CHECK 3: Duplicate primary keys ───────────────────────
    pk_cols = PRIMARY_KEYS.get(dataset_name, [])
    if pk_cols:
        dup_count = data.duplicated(subset=pk_cols).sum()
        if dup_count > 0:
            msg = f"Duplicate primary keys found: {dup_count:,} rows in {pk_cols}"
            logger.error(f"  [CRITICAL] {msg}")
            critical_failures.append(msg)
            failed += 1
        else:
            logger.info(f"  [PASS] No duplicate primary keys in {pk_cols}")
            passed += 1

    # ── CHECK 4: Date columns contain valid dates ─────────────
    date_cols = [c for c in data.columns
                 if any(x in c.lower() for x in ["dt", "date", "dob", "dod"])]
    for col in date_cols:
        # Exclude 'NA' placeholder before parsing
        series = data[col][data[col] != "NA"].dropna()
        invalid = pd.to_datetime(series, errors="coerce").isna().sum()
        if invalid > 0:
            logger.warning(f"  [WARNING] '{col}': {invalid:,} unparseable dates")
            failed += 1
        else:
            logger.info(f"  [PASS] All dates valid in '{col}'")
            passed += 1

    # ── CHECK 5: No negative numeric values ───────────────────
    numeric_cols = [c for c in data.columns
                    if any(x in c.lower() for x in ["amt", "reimbursed", "deductible"])]
    for col in numeric_cols:
        series   = pd.to_numeric(data[col], errors="coerce")
        neg_count = (series < 0).sum()
        if neg_count > 0:
            logger.warning(f"  [WARNING] '{col}': {neg_count:,} negative values")
            failed += 1
        else:
            logger.info(f"  [PASS] No negative values in '{col}'")
            passed += 1

    # ── Summary ───────────────────────────────────────────────
    logger.info(f"  Validation summary: {passed} passed, {failed} failed")

    # Stop pipeline if any critical check failed
    if critical_failures:
        raise Exception(
            f"Critical validation failed for '{dataset_name}':\n" +
            "\n".join(critical_failures)
        )

    return {
        "dataset": dataset_name,
        "passed":  passed,
        "failed":  failed,
        "critical_failures": critical_failures
    }


def validate_all_datasets(dataframes):
    """
    Validate all source DataFrames.

    Args:
        dataframes: dict of {dataset_name: DataFrame}

    Returns:
        dict: {dataset_name: validation_result}
    """
    logger.info("=" * 50)
    logger.info("Validating all datasets")
    logger.info("=" * 50)

    all_results = {}

    for dataset_name, df in dataframes.items():
        result = validate_dataset(df, dataset_name)
        all_results[dataset_name] = result
        logger.info(f"  {dataset_name}: PASSED ({result['passed']} checks)")

    logger.info("All datasets passed validation")
    return all_results
