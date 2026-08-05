# ============================================================
# FILE: src/bronze/reader.py
# PURPOSE: Reads source CSV files into pandas DataFrames.
#          Bronze rule: read everything as text (strings).
#          No type conversion here — that happens in Silver.
#          Adds audit columns: ingestion_timestamp, source_file_name, batch_id.
# ============================================================

import pandas as pd
import os
from datetime import datetime
from src.utils.logger import get_logger

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from config.config import SOURCE_DIR, SOURCE_FILES

logger = get_logger(__name__)


def read_source_file(dataset_name):
    """
    Read one source CSV file into a DataFrame.

    Args:
        dataset_name: 'provider', 'inpatient', 'outpatient', or 'beneficiary'

    Returns:
        pandas DataFrame with raw data + 3 audit columns added
    """
    file_name = SOURCE_FILES[dataset_name]
    file_path = os.path.join(SOURCE_DIR, file_name)

    logger.info(f"Reading {dataset_name} file: {file_path}")

    # Check file exists before reading
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"Source file not found: {file_path}")

    file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
    logger.info(f"File size: {file_size_mb:.2f} MB")

    # Read as string — preserves source data exactly
    # keep_default_na=False and na_values=[] prevent pandas
    # from auto-converting 'NA' text to NaN
    df = pd.read_csv(
        file_path,
        dtype=str,
        encoding="utf-8",
        keep_default_na=False,
        na_values=[]
    )

    # Add audit columns
    batch_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    df["ingestion_timestamp"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    df["source_file_name"]    = file_name
    df["batch_id"]            = batch_id

    logger.info(f"Read complete: {len(df):,} rows, {len(df.columns)} columns")

    return df


def read_all_sources():
    """
    Read all four source CSV files.

    Returns:
        dict: {dataset_name: DataFrame}
    """
    logger.info("=" * 50)
    logger.info("Reading all source files")
    logger.info("=" * 50)

    dataframes = {}

    for dataset_name in SOURCE_FILES.keys():
        df = read_source_file(dataset_name)
        dataframes[dataset_name] = df
        logger.info(f"  {dataset_name}: {len(df):,} rows loaded")

    total = sum(len(df) for df in dataframes.values())
    logger.info(f"Total rows read across all files: {total:,}")

    return dataframes
