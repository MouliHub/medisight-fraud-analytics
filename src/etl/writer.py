# ============================================================
# FILE: src/bronze/writer.py
# PURPOSE: Writes validated DataFrames to SQL Server Bronze tables.
#          Always truncates the table before loading (full refresh).
#          Verifies row count after write to confirm all rows landed.
# ============================================================

import pandas as pd
import os
from datetime import datetime
from sqlalchemy import text
from src.utils.logger import get_logger

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from config.config import BRONZE_TABLES, CHUNK_SIZE

logger = get_logger(__name__)


def write_to_bronze(df, dataset_name, engine):
    """
    Write one DataFrame to its Bronze SQL Server table.

    Steps:
    1. Truncate the table (full refresh pattern)
    2. Write DataFrame in chunks
    3. Verify row count matches

    Args:
        df:           pandas DataFrame to write
        dataset_name: 'provider', 'inpatient', 'outpatient', or 'beneficiary'
        engine:       SQLAlchemy engine from db_connector.py

    Returns:
        int: number of rows written
    """
    table_name        = BRONZE_TABLES[dataset_name]
    schema, tbl       = table_name.split(".")
    rows_to_write     = len(df)

    logger.info(f"Writing {dataset_name} to {table_name}")
    logger.info(f"  Rows to write: {rows_to_write:,}")

    # Step 1: Truncate table before load
    logger.info(f"  Truncating {table_name}...")
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE {table_name}"))
    logger.info(f"  Truncated successfully")

    # Step 2: Write DataFrame to SQL Server in chunks
    start_time = datetime.now()

    df.to_sql(
        name      = tbl,
        con       = engine,
        schema    = schema,
        if_exists = "append",   # table already exists, just append rows
        index     = False,       # don't write pandas row index to SQL
        chunksize = CHUNK_SIZE   # write in batches of 1000 rows
    )

    duration = (datetime.now() - start_time).total_seconds()

    # Step 3: Verify row count in SQL Server
    with engine.connect() as conn:
        result      = conn.execute(text(f"SELECT COUNT(*) FROM {table_name}"))
        rows_in_db  = result.fetchone()[0]

    logger.info(f"  Rows written:  {rows_in_db:,}")
    logger.info(f"  Duration:      {duration:.2f} seconds")

    # Reconciliation check — every row must have landed
    if rows_in_db != rows_to_write:
        raise Exception(
            f"Row count mismatch for {dataset_name}: "
            f"wrote {rows_to_write:,}, but {rows_in_db:,} found in database"
        )

    logger.info(f"  {dataset_name}: write successful")
    return rows_in_db


def write_all_to_bronze(dataframes, engine):
    """
    Write all DataFrames to Bronze SQL tables.

    Args:
        dataframes: dict of {dataset_name: DataFrame}
        engine:     SQLAlchemy engine

    Returns:
        dict: {dataset_name: rows_written}
    """
    logger.info("=" * 50)
    logger.info("Writing all datasets to Bronze")
    logger.info("=" * 50)

    results     = {}
    total_rows  = 0

    for dataset_name, df in dataframes.items():
        rows = write_to_bronze(df, dataset_name, engine)
        results[dataset_name] = rows
        total_rows += rows

    logger.info(f"Total rows written to Bronze: {total_rows:,}")
    return results
