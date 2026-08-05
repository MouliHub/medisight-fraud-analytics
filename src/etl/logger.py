# ============================================================
# FILE: src/utils/logger.py
# PURPOSE: Simple logging setup for the MediSight pipeline.
#          Every module imports this to log messages to both
#          the console (so you see progress) and a log file
#          (permanent record of every pipeline run).
# ============================================================

import logging
import os
from datetime import datetime

# Log file location — one file per pipeline run
LOG_DIR = r"D:\1_my_projects\HEALTHCARE PROVIDER FRAUD DETECTION ANALYSIS\python_pipeline\logs"


def get_logger(name):
    """
    Create and return a logger for any module.

    Usage:
        from src.utils.logger import get_logger
        logger = get_logger(__name__)
        logger.info("Starting pipeline...")
        logger.warning("Null values found")
        logger.error("File not found")
    """

    # Create logs folder if it doesn't exist
    os.makedirs(LOG_DIR, exist_ok=True)

    # Log file named with today's date
    log_file = os.path.join(LOG_DIR, f"pipeline_{datetime.now().strftime('%Y%m%d')}.log")

    # Create logger
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)

    # Avoid adding duplicate handlers if logger already exists
    if logger.handlers:
        return logger

    # Format: [2026-07-01 10:30:15] INFO - reader - Reading provider file...
    formatter = logging.Formatter(
        "[%(asctime)s] %(levelname)s - %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Handler 1: Show logs in the terminal (console)
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    # Handler 2: Save logs to a file
    file_handler = logging.FileHandler(log_file, encoding="utf-8")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger
