/* ============================================================
   FILE: 08_gold_create_tables.sql
   PURPOSE: Create Gold layer star schema with surrogate keys,
            proper constraints, and indexes for Power BI
            query performance.

   DESIGN DECISIONS:
   - Surrogate keys (INT IDENTITY) on all dimension tables
     for stable, efficient joining — natural keys kept for
     traceability back to Silver/Bronze
   - UNIQUE constraints on natural keys in dimension tables
     to enforce one-row-per-entity at database level
   - NOT NULL on all foreign keys in fact table — a fact
     row with a missing dimension link is analytically useless
   - Indexes on fact table foreign key columns — Power BI
     joins fact to dims on every visual render; without indexes
     each join scans 558K rows
   - Indexes on commonly filtered/grouped columns
     (claim_type, is_potential_fraud, claim_start_date_key)
   - Aggregation tables indexed on their lookup/join columns
     since Power BI map/trend visuals group by state/month

   RUN FREQUENCY: Once, or whenever Gold schema changes.
                  Safe to re-run (uses IF OBJECT_ID drop pattern)
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- DIMENSION TABLE 1: dim_provider
-- =====================================================
IF OBJECT_ID('gold.dim_provider', 'U') IS NOT NULL
    DROP TABLE gold.dim_provider;
GO

CREATE TABLE gold.dim_provider (
    -- Surrogate key (stable internal identifier)
    provider_key            INT IDENTITY(1,1)   NOT NULL,
    -- Natural key (from source system)
    provider_id             VARCHAR(50)         NOT NULL,
    is_potential_fraud      BIT                 NOT NULL,
    fraud_label             VARCHAR(10)         NOT NULL,   -- 'Fraud' / 'Not Fraud'
    dwh_created_at          DATETIME2           NOT NULL DEFAULT SYSDATETIME(),

    -- Primary key on surrogate
    CONSTRAINT PK_dim_provider PRIMARY KEY CLUSTERED (provider_key),

    -- Unique constraint on natural key
    -- Enforces one row per provider at database level
    CONSTRAINT UQ_dim_provider_id UNIQUE (provider_id)
);
GO

-- Index on fraud label for Page 3 (Provider Risk) filtering
CREATE NONCLUSTERED INDEX IX_dim_provider_fraud
ON gold.dim_provider (is_potential_fraud)
INCLUDE (provider_id, fraud_label);
GO

-- =====================================================
-- DIMENSION TABLE 2: dim_beneficiary
-- =====================================================
IF OBJECT_ID('gold.dim_beneficiary', 'U') IS NOT NULL
    DROP TABLE gold.dim_beneficiary;
GO

CREATE TABLE gold.dim_beneficiary (
    beneficiary_key             INT IDENTITY(1,1)   NOT NULL,
    beneficiary_id              VARCHAR(50)         NOT NULL,
    date_of_birth               DATE                NULL,
    date_of_death               DATE                NULL,
    gender                      VARCHAR(10)         NULL,
    renal_disease_indicator     TINYINT             NULL,
    state_code                  INT                 NULL,
    county_code                 INT                 NULL,
    patient_age                 INT                 NULL,
    age_group                   VARCHAR(20)         NULL,
    is_deceased                 BIT                 NULL,
    chronic_condition_count     INT                 NULL,
    has_alzheimer               TINYINT             NULL,
    has_heart_failure            TINYINT             NULL,
    has_kidney_disease          TINYINT             NULL,
    has_cancer                  TINYINT             NULL,
    has_obstr_pulmonary         TINYINT             NULL,
    has_depression              TINYINT             NULL,
    has_diabetes                TINYINT             NULL,
    has_ischemic_heart          TINYINT             NULL,
    has_osteoporosis            TINYINT             NULL,
    has_rheumatoid_arthritis    TINYINT             NULL,
    has_stroke                  TINYINT             NULL,
    ip_annual_reimbursement_amt INT                 NULL,
    ip_annual_deductible_amt    INT                 NULL,
    op_annual_reimbursement_amt INT                 NULL,
    op_annual_deductible_amt    INT                 NULL,
    dwh_created_at              DATETIME2           NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_dim_beneficiary PRIMARY KEY CLUSTERED (beneficiary_key),
    CONSTRAINT UQ_dim_beneficiary_id UNIQUE (beneficiary_id)
);
GO

-- Index on state_code for geographic analysis (Page 6)
CREATE NONCLUSTERED INDEX IX_dim_beneficiary_state
ON gold.dim_beneficiary (state_code)
INCLUDE (beneficiary_id, age_group, gender, chronic_condition_count, is_deceased);
GO

-- Index on age_group for Page 4 (Beneficiary analysis)
CREATE NONCLUSTERED INDEX IX_dim_beneficiary_age_group
ON gold.dim_beneficiary (age_group)
INCLUDE (beneficiary_id, patient_age, chronic_condition_count);
GO

-- =====================================================
-- DIMENSION TABLE 3: dim_date
-- Generated calendar table
-- =====================================================
IF OBJECT_ID('gold.dim_date', 'U') IS NOT NULL
    DROP TABLE gold.dim_date;
GO

CREATE TABLE gold.dim_date (
    -- Integer YYYYMMDD key — faster than DATE for joins
    date_key        INT             NOT NULL,
    full_date       DATE            NOT NULL,
    day_of_month    INT             NOT NULL,
    day_name        VARCHAR(10)     NOT NULL,
    week_of_year    INT             NOT NULL,
    month_num       INT             NOT NULL,
    month_name      VARCHAR(10)     NOT NULL,
    quarter_num     INT             NOT NULL,
    quarter_name    VARCHAR(6)      NOT NULL,
    year_num        INT             NOT NULL,
    year_month      VARCHAR(7)      NOT NULL,   -- 'YYYY-MM' for trend charts
    is_weekend      BIT             NOT NULL,
    dwh_created_at  DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_dim_date PRIMARY KEY CLUSTERED (date_key)
);
GO

-- Index on year_month for trend analysis (Page 6)
CREATE NONCLUSTERED INDEX IX_dim_date_year_month
ON gold.dim_date (year_num, month_num)
INCLUDE (year_month, month_name, quarter_name);
GO

-- =====================================================
-- DIMENSION TABLE 4: dim_geography
-- State-level lookup with CMS code mapping
-- =====================================================
IF OBJECT_ID('gold.dim_geography', 'U') IS NOT NULL
    DROP TABLE gold.dim_geography;
GO

CREATE TABLE gold.dim_geography (
    geo_key         INT IDENTITY(1,1)   NOT NULL,
    state_code      INT                 NOT NULL,
    state_name      VARCHAR(50)         NOT NULL,
    state_abbr      VARCHAR(2)          NOT NULL,
    region          VARCHAR(20)         NOT NULL,
    dwh_created_at  DATETIME2           NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_dim_geography PRIMARY KEY CLUSTERED (geo_key),
    CONSTRAINT UQ_dim_geography_state UNIQUE (state_code)
);
GO

-- =====================================================
-- FACT TABLE: fact_claims
-- Central table — all foreign keys + all measures
-- =====================================================
IF OBJECT_ID('gold.fact_claims', 'U') IS NOT NULL
    DROP TABLE gold.fact_claims;
GO

CREATE TABLE gold.fact_claims (
    -- Surrogate primary key
    claim_key                   INT IDENTITY(1,1)   NOT NULL,

    -- Natural key (for traceability back to Silver)
    claim_id                    VARCHAR(50)         NOT NULL,

    -- Foreign keys to dimension tables (NOT NULL enforced)
    -- A fact row without a dimension link is analytically broken
    provider_key                INT                 NOT NULL,
    beneficiary_key             INT                 NOT NULL,
    claim_start_date_key        INT                 NOT NULL,
    geo_key                     INT                 NULL,   -- NULL allowed (code 54 = Unknown)

    -- Degenerate dimensions (low cardinality, no separate dim)
    claim_type                  VARCHAR(15)         NOT NULL,
    is_potential_fraud          BIT                 NOT NULL,

    -- Measures
    claim_reimbursement_amt     INT                 NULL,
    deductible_amt_paid         DECIMAL(10,2)       NULL,
    claim_duration_days         INT                 NULL,
    admission_duration_days     INT                 NULL,
    diagnosis_code_count        INT                 NULL,
    procedure_code_count        INT                 NULL,

    -- Flags (SUM in DAX gives count of flagged rows)
    is_zero_reimbursement       BIT                 NULL,
    is_same_day_discharge       BIT                 NULL,

    dwh_created_at              DATETIME2           NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_fact_claims PRIMARY KEY CLUSTERED (claim_key),
    CONSTRAINT UQ_fact_claims_id UNIQUE (claim_id)
    -- NOTE: FK relationships are defined logically (not enforced physically)
    -- Data quality is guaranteed by the Silver validation layer.
    -- This is standard data warehouse practice — physical FK enforcement
    -- blocks TRUNCATE/reload patterns used in full-refresh pipelines.
    -- Relationships are set manually in Power BI using matching key columns.
);
GO

-- -----------------------------------------------
-- Indexes on fact_claims
-- These are the most important indexes in the schema
-- Every Power BI visual joins or filters on these columns
-- -----------------------------------------------

-- FK indexes — SQL Server does NOT auto-create these
-- Without them, every dim-to-fact join scans 558K rows
CREATE NONCLUSTERED INDEX IX_fact_provider_key
ON gold.fact_claims (provider_key)
INCLUDE (claim_reimbursement_amt, claim_type, is_potential_fraud);
GO

CREATE NONCLUSTERED INDEX IX_fact_beneficiary_key
ON gold.fact_claims (beneficiary_key)
INCLUDE (claim_reimbursement_amt, claim_type, claim_duration_days);
GO

CREATE NONCLUSTERED INDEX IX_fact_date_key
ON gold.fact_claims (claim_start_date_key)
INCLUDE (claim_reimbursement_amt, claim_type, provider_key);
GO

CREATE NONCLUSTERED INDEX IX_fact_geo_key
ON gold.fact_claims (geo_key)
INCLUDE (claim_reimbursement_amt, claim_type);
GO

-- Composite index for claim_type filtering
-- Page 5 (IP vs OP) filters on claim_type constantly
CREATE NONCLUSTERED INDEX IX_fact_claim_type
ON gold.fact_claims (claim_type, is_potential_fraud)
INCLUDE (claim_reimbursement_amt, claim_duration_days,
         admission_duration_days, diagnosis_code_count,
         procedure_code_count, is_zero_reimbursement,
         is_same_day_discharge);
GO

-- =====================================================
-- AGGREGATION TABLE 1: agg_provider_summary
-- Provider-level rollup for Pages 2 and 3
-- =====================================================
IF OBJECT_ID('gold.agg_provider_summary', 'U') IS NOT NULL
    DROP TABLE gold.agg_provider_summary;
GO

CREATE TABLE gold.agg_provider_summary (
    provider_id                 VARCHAR(50)     NOT NULL,
    is_potential_fraud          BIT             NOT NULL,
    fraud_label                 VARCHAR(10)     NOT NULL,
    total_claims                INT             NULL,
    total_ip_claims             INT             NULL,
    total_op_claims             INT             NULL,
    total_reimbursement         BIGINT          NULL,
    avg_reimbursement_per_claim DECIMAL(12,2)   NULL,
    max_reimbursement           INT             NULL,
    total_deductible            DECIMAL(14,2)   NULL,
    unique_beneficiaries        INT             NULL,
    unique_attending_physicians INT             NULL,
    avg_claim_duration_days     DECIMAL(8,2)    NULL,
    avg_admission_duration_days DECIMAL(8,2)    NULL,
    avg_diagnosis_code_count    DECIMAL(6,2)    NULL,
    avg_procedure_code_count    DECIMAL(6,2)    NULL,
    zero_reimbursement_claims   INT             NULL,
    same_day_discharge_claims   INT             NULL,
    deceased_patient_claims     INT             NULL,
    dwh_created_at              DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_agg_provider PRIMARY KEY CLUSTERED (provider_id)
);
GO

-- Index for fraud filtering on provider summary (Page 3)
CREATE NONCLUSTERED INDEX IX_agg_provider_fraud
ON gold.agg_provider_summary (is_potential_fraud)
INCLUDE (provider_id, total_claims, total_reimbursement,
         avg_reimbursement_per_claim, deceased_patient_claims);
GO

-- =====================================================
-- AGGREGATION TABLE 2: agg_state_monthly
-- State + month rollup for Page 6
-- =====================================================
IF OBJECT_ID('gold.agg_state_monthly', 'U') IS NOT NULL
    DROP TABLE gold.agg_state_monthly;
GO

CREATE TABLE gold.agg_state_monthly (
    state_code                  INT             NOT NULL,
    state_name                  VARCHAR(50)     NOT NULL,
    state_abbr                  VARCHAR(2)      NOT NULL,
    region                      VARCHAR(20)     NOT NULL,
    year_num                    INT             NOT NULL,
    month_num                   INT             NOT NULL,
    month_name                  VARCHAR(10)     NOT NULL,
    year_month                  VARCHAR(7)      NOT NULL,
    total_claims                INT             NULL,
    total_ip_claims             INT             NULL,
    total_op_claims             INT             NULL,
    total_reimbursement         BIGINT          NULL,
    avg_reimbursement_per_claim DECIMAL(12,2)   NULL,
    unique_providers            INT             NULL,
    unique_beneficiaries        INT             NULL,
    fraud_provider_claims       INT             NULL,
    dwh_created_at              DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_agg_state_monthly
        PRIMARY KEY CLUSTERED (state_code, year_num, month_num)
);
GO

-- Index for region grouping and trend analysis
CREATE NONCLUSTERED INDEX IX_agg_state_monthly_region
ON gold.agg_state_monthly (region, year_num, month_num)
INCLUDE (total_reimbursement, total_claims, fraud_provider_claims);
GO

-- =====================================================
-- AGGREGATION TABLE 3: agg_chronic_disease
-- Disease-level rollup for Page 4
-- =====================================================
IF OBJECT_ID('gold.agg_chronic_disease', 'U') IS NOT NULL
    DROP TABLE gold.agg_chronic_disease;
GO

CREATE TABLE gold.agg_chronic_disease (
    disease_name                        VARCHAR(50)     NOT NULL,
    total_beneficiaries                 INT             NULL,
    pct_of_all_beneficiaries            DECIMAL(6,2)    NULL,
    total_claims                        INT             NULL,
    total_reimbursement                 BIGINT          NULL,
    avg_reimbursement_per_patient       DECIMAL(12,2)   NULL,
    avg_chronic_count_for_patients_with_this DECIMAL(6,2) NULL,
    dwh_created_at                      DATETIME2       NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_agg_chronic_disease PRIMARY KEY CLUSTERED (disease_name)
);
GO

PRINT 'Gold tables created successfully with constraints and indexes.';
GO
