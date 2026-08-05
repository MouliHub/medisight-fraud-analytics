/* ============================================================
   FILE: 06_silver_create_tables.sql
   PURPOSE: Create Silver layer tables - cleaned, validated,
            properly typed, renamed, and enriched versions of
            the Bronze raw tables.

   DESIGN DECISIONS:
   - snake_case naming convention throughout
   - Proper data types (DATE, INT, BIT) instead of VARCHAR
   - NA placeholders removed (converted to NULL or 0)
   - Derived columns added (age, durations, counts, flags)
   - Inpatient and Outpatient combined into one stg_claims table
   - Columns removed: Race, DiagnosisGroupCode,
     NoOfMonths_PartACov, NoOfMonths_PartBCov
   - Chronic condition flags recoded: 1=has condition, 0=does not
   - Gender decoded: Male/Female
   - RenalDiseaseIndicator standardized: 1/0
   - PotentialFraud standardized: 1/0

   RUN FREQUENCY: Once, or whenever Silver schema changes.
                  Safe to re-run (uses IF OBJECT_ID drop pattern).
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- SILVER TABLE 1: stg_provider
-- Source: bronze.raw_provider_labels
-- One row per provider with fraud label
-- =====================================================
IF OBJECT_ID('silver.stg_provider', 'U') IS NOT NULL
    DROP TABLE silver.stg_provider;
GO

CREATE TABLE silver.stg_provider (
    provider_id             VARCHAR(50)     NOT NULL,
    is_potential_fraud      BIT             NOT NULL,   -- 1=Yes, 0=No
    dwh_created_at          DATETIME2       DEFAULT SYSDATETIME()
);
GO

-- =====================================================
-- SILVER TABLE 2: stg_beneficiary
-- Source: bronze.raw_beneficiary
-- One row per patient with demographics + conditions
-- =====================================================
IF OBJECT_ID('silver.stg_beneficiary', 'U') IS NOT NULL
    DROP TABLE silver.stg_beneficiary;
GO

CREATE TABLE silver.stg_beneficiary (
    -- Identity
    beneficiary_id                  VARCHAR(50)     NOT NULL,
    date_of_birth                   DATE            NULL,
    date_of_death                   DATE            NULL,       -- NULL = still living
    gender                          VARCHAR(10)     NULL,       -- 'Male' / 'Female'
    renal_disease_indicator         TINYINT         NULL,       -- 1=Yes, 0=No

    -- Geography
    state_code                      INT             NULL,
    county_code                     INT             NULL,

    -- Chronic conditions (recoded: 1=has condition, 0=does not)
    has_alzheimer                   TINYINT         NULL,
    has_heart_failure                TINYINT         NULL,
    has_kidney_disease              TINYINT         NULL,
    has_cancer                      TINYINT         NULL,
    has_obstr_pulmonary             TINYINT         NULL,
    has_depression                  TINYINT         NULL,
    has_diabetes                    TINYINT         NULL,
    has_ischemic_heart              TINYINT         NULL,
    has_osteoporosis                TINYINT         NULL,
    has_rheumatoid_arthritis        TINYINT         NULL,
    has_stroke                      TINYINT         NULL,

    -- Financial
    ip_annual_reimbursement_amt     INT             NULL,
    ip_annual_deductible_amt        INT             NULL,
    op_annual_reimbursement_amt     INT             NULL,
    op_annual_deductible_amt        INT             NULL,

    -- Derived columns
    patient_age                     INT             NULL,       -- as of 2009-12-31
    age_group                       VARCHAR(20)     NULL,       -- e.g. '65-74'
    is_deceased                     BIT             NULL,       -- 1=deceased, 0=alive
    chronic_condition_count         INT             NULL,       -- sum of all 11 flags

    dwh_created_at                  DATETIME2       DEFAULT SYSDATETIME()
);
GO

-- =====================================================
-- SILVER TABLE 3: stg_claims
-- Source: bronze.raw_inpatient + bronze.raw_outpatient
-- Combined, one row per claim, with claim_type flag
-- =====================================================
IF OBJECT_ID('silver.stg_claims', 'U') IS NOT NULL
    DROP TABLE silver.stg_claims;
GO

CREATE TABLE silver.stg_claims (
    -- Identity
    claim_id                        VARCHAR(50)     NOT NULL,
    beneficiary_id                  VARCHAR(50)     NOT NULL,
    provider_id                     VARCHAR(50)     NOT NULL,
    claim_type                      VARCHAR(15)     NOT NULL,   -- 'Inpatient'/'Outpatient'

    -- Dates
    claim_start_date                DATE            NULL,
    claim_end_date                  DATE            NULL,
    admission_date                  DATE            NULL,       -- Inpatient only
    discharge_date                  DATE            NULL,       -- Inpatient only

    -- Financial
    claim_reimbursement_amt         INT             NULL,
    deductible_amt_paid             DECIMAL(10,2)   NULL,       -- 0 where NA in source

    -- Physicians
    attending_physician_id          VARCHAR(50)     NULL,
    operating_physician_id          VARCHAR(50)     NULL,       -- NULL where NA
    other_physician_id              VARCHAR(50)     NULL,       -- NULL where NA

    -- Diagnosis codes (kept as-is for reference, cleaned of NA)
    diagnosis_code_1                VARCHAR(20)     NULL,
    diagnosis_code_2                VARCHAR(20)     NULL,
    diagnosis_code_3                VARCHAR(20)     NULL,
    diagnosis_code_4                VARCHAR(20)     NULL,
    diagnosis_code_5                VARCHAR(20)     NULL,
    diagnosis_code_6                VARCHAR(20)     NULL,
    diagnosis_code_7                VARCHAR(20)     NULL,
    diagnosis_code_8                VARCHAR(20)     NULL,
    diagnosis_code_9                VARCHAR(20)     NULL,
    diagnosis_code_10               VARCHAR(20)     NULL,

    -- Procedure codes (kept as-is, cleaned of NA)
    procedure_code_1                VARCHAR(20)     NULL,
    procedure_code_2                VARCHAR(20)     NULL,
    procedure_code_3                VARCHAR(20)     NULL,
    procedure_code_4                VARCHAR(20)     NULL,
    procedure_code_5                VARCHAR(20)     NULL,
    procedure_code_6                VARCHAR(20)     NULL,

    -- Derived columns
    claim_duration_days             INT             NULL,       -- claim_end - claim_start
    admission_duration_days         INT             NULL,       -- discharge - admission (IP only)
    diagnosis_code_count            INT             NULL,       -- count of non-null diag codes
    procedure_code_count            INT             NULL,       -- count of non-null proc codes
    is_zero_reimbursement           BIT             NULL,       -- 1 if reimbursement = 0
    is_same_day_discharge           BIT             NULL,       -- 1 if admit = discharge (IP only)

    dwh_created_at                  DATETIME2       DEFAULT SYSDATETIME()
);
GO

PRINT 'Silver tables created successfully.';
GO
