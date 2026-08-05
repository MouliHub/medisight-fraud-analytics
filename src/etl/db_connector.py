# ============================================================
# FILE: src/utils/db_connector.py
# PURPOSE: Creates and returns a SQL Server connection.
#          All modules use this instead of writing their own
#          connection code — one place to manage DB settings.
# ============================================================

from sqlalchemy import create_engine, text
from src.utils.logger import get_logger

# Import connection string from config
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from config.config import DB_CONNECTION_STRING, DB_SERVER, DB_NAME

logger = get_logger(__name__)


def get_engine():
    """
    Create and return a SQLAlchemy engine for SQL Server.
    Uses Windows Authentication — no username or password needed.

    Returns:
        SQLAlchemy engine object

    Raises:
        Exception if connection fails
    """
    try:
        logger.info(f"Connecting to SQL Server: {DB_SERVER} / {DB_NAME}")

        engine = create_engine(DB_CONNECTION_STRING, fast_executemany=True)

        # Test the connection immediately
        with engine.connect() as conn:
            result = conn.execute(text("SELECT DB_NAME()"))
            db = result.fetchone()[0]
            logger.info(f"Connected successfully to: {db}")

        return engine

    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        logger.error("Make sure SQL Server is running and server name is correct in config.py")
        raise
