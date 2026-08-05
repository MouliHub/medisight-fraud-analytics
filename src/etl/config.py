# ============================================================
# FILE: config/config.py
# PURPOSE: Central configuration for the MediSight pipeline.
#          All settings in one place — paths, database,
#          table names, and validation rules.
#          No hardcoded values anywhere else in the project.
# ============================================================

# ── Source file paths ────────────────────────────────────────
SOURCE_DIR = r"D:\1_my_projects\HEALTHCARE PROVIDER FRAUD DETECTION ANALYSIS\archive"

SOURCE_FILES = {
    "provider":    "Train-1542865627584.csv",
    "inpatient":   "Train_Inpatientdata-1542865627584.csv",
    "outpatient":  "Train_Outpatientdata-1542865627584.csv",
    "beneficiary": "Train_Beneficiarydata-1542865627584.csv",
}

# ── Database settings ─────────────────────────────────────────
DB_SERVER   = "LAPTOP-03S07GO9"
DB_NAME     = "MediSight"
DB_DRIVER   = "ODBC Driver 17 for SQL Server"

# SQLAlchemy connection string (Windows Authentication)
DB_CONNECTION_STRING = (
    f"mssql+pyodbc://{DB_SERVER}/{DB_NAME}"
    f"?driver={DB_DRIVER.replace(' ', '+')}"
    f"&trusted_connection=yes"
)

# ── Bronze table names ────────────────────────────────────────
BRONZE_TABLES = {
    "provider":    "bronze.raw_provider_labels",
    "inpatient":   "bronze.raw_inpatient",
    "outpatient":  "bronze.raw_outpatient",
    "beneficiary": "bronze.raw_beneficiary",
}

# ── Expected row counts (confirmed during SQL profiling) ──────
EXPECTED_ROW_COUNTS = {
    "provider":    5410,
    "inpatient":   40474,
    "outpatient":  517737,
    "beneficiary": 138556,
}

# ── Columns that must never be NULL ──────────────────────────
NOT_NULL_COLUMNS = {
    "provider":    ["Provider", "PotentialFraud"],
    "inpatient":   ["BeneID", "ClaimID", "Provider"],
    "outpatient":  ["BeneID", "ClaimID", "Provider"],
    "beneficiary": ["BeneID", "DOB", "Gender"],
}

# ── Primary key columns for duplicate detection ───────────────
PRIMARY_KEYS = {
    "provider":    ["Provider"],
    "inpatient":   ["ClaimID"],
    "outpatient":  ["ClaimID"],
    "beneficiary": ["BeneID"],
}

# ── Write settings ────────────────────────────────────────────
CHUNK_SIZE = 1000   # rows per batch when writing to SQL Server
