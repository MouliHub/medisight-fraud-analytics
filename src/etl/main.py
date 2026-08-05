# ============================================================
# FILE: main.py
# PURPOSE: Entry point for the MediSight Bronze ETL pipeline.
#          Run this file to execute the complete pipeline:
#
#              python main.py
#
# Pipeline Steps:
#   1. Check source files exist
#   2. Connect to SQL Server
#   3. Read all 4 CSV files
#   4. Profile all datasets
#   5. Validate all datasets
#   6. Write to Bronze SQL Server tables
#   7. Final reconciliation check
# ============================================================

import sys
import os
from datetime import datetime

# Add project root to path so all imports work
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config.config import SOURCE_DIR, SOURCE_FILES, EXPECTED_ROW_COUNTS
from src.utils.logger import get_logger
from src.utils.db_connector import get_engine
from src.bronze.reader import read_all_sources
from src.bronze.profiler import profile_all_datasets
from src.bronze.validator import validate_all_datasets
from src.bronze.writer import write_all_to_bronze

logger = get_logger("main")


def check_source_files():
    """Check all source CSV files exist before starting."""
    logger.info("Checking source files...")
    all_found = True

    for name, filename in SOURCE_FILES.items():
        path = os.path.join(SOURCE_DIR, filename)
        if os.path.exists(path):
            size_mb = os.path.getsize(path) / (1024 * 1024)
            logger.info(f"  [FOUND] {name}: {filename} ({size_mb:.1f} MB)")
        else:
            logger.error(f"  [MISSING] {name}: {path}")
            all_found = False

    if not all_found:
        raise Exception("One or more source files are missing. Check paths in config.py")

    logger.info("All source files found")


def run_pipeline():
    """
    Run the complete Bronze ETL pipeline.
    Returns 'SUCCESS' or 'FAILED'.
    """
    start_time = datetime.now()

    logger.info("=" * 60)
    logger.info("  MediSight ETL Pipeline — Bronze Layer")
    logger.info(f"  Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 60)

    try:
        # ── Step 1: Check source files ────────────────────────
        logger.info("Step 1: Checking source files")
        check_source_files()

        # ── Step 2: Connect to SQL Server ─────────────────────
        logger.info("Step 2: Connecting to SQL Server")
        engine = get_engine()

        # ── Step 3: Read source CSV files ─────────────────────
        logger.info("Step 3: Reading source files")
        dataframes = read_all_sources()

        # ── Step 4: Profile datasets ──────────────────────────
        logger.info("Step 4: Profiling datasets")
        profile_all_datasets(dataframes)

        # ── Step 5: Validate datasets ─────────────────────────
        # Pipeline stops here if any critical check fails
        logger.info("Step 5: Validating datasets")
        validate_all_datasets(dataframes)

        # ── Step 6: Write to Bronze SQL tables ────────────────
        logger.info("Step 6: Writing to Bronze SQL tables")
        write_results = write_all_to_bronze(dataframes, engine)

        # ── Step 7: Final reconciliation ──────────────────────
        logger.info("Step 7: Final reconciliation")
        all_match = True
        for dataset_name, rows_written in write_results.items():
            expected = EXPECTED_ROW_COUNTS.get(dataset_name)
            match    = rows_written == expected
            status   = "MATCH" if match else "MISMATCH"
            logger.info(
                f"  {dataset_name}: "
                f"{rows_written:,} rows written | "
                f"Expected: {expected:,} | {status}"
            )
            if not match:
                all_match = False

        if not all_match:
            raise Exception("Reconciliation failed: row counts do not match expected values")

        # ── Pipeline Complete ─────────────────────────────────
        end_time  = datetime.now()
        duration  = (end_time - start_time).total_seconds()
        total_rows = sum(write_results.values())

        logger.info("=" * 60)
        logger.info("  Bronze Pipeline Completed Successfully")
        logger.info(f"  Total rows loaded : {total_rows:,}")
        logger.info(f"  Total duration    : {duration:.2f} seconds")
        logger.info(f"  Finished          : {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("=" * 60)
        logger.info("Next step: Run silver layer -> EXEC silver.load_silver in SSMS")

        return "SUCCESS"

    except Exception as e:
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        logger.error("=" * 60)
        logger.error("  Bronze Pipeline FAILED")
        logger.error(f"  Error   : {str(e)}")
        logger.error(f"  Duration: {duration:.2f} seconds")
        logger.error("=" * 60)

        return "FAILED"


# ── Entry point ───────────────────────────────────────────────
if __name__ == "__main__":
    result = run_pipeline()

    # Exit code 1 = failure (used by schedulers to detect errors)
    if result == "FAILED":
        sys.exit(1)
    else:
        sys.exit(0)
