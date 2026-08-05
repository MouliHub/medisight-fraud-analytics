/* ============================================================
   FILE: 10_gold_validation.sql
   PURPOSE: Comprehensive validation of Gold layer after loading.
            Verifies row counts, referential integrity, business
            KPI ranges, and aggregation accuracy before Power BI
            connects to Gold tables.

   RUN FREQUENCY: After every run of EXEC gold.load_gold
   NOTE: Read-only. Does not modify any data.
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- SECTION 1: ROW COUNT VERIFICATION
-- =====================================================
PRINT '--- Section 1: Row Count Verification ---';

SELECT 'gold.dim_provider'        AS table_name, COUNT(*) AS row_count, 5410   AS expected FROM gold.dim_provider
UNION ALL
SELECT 'gold.dim_beneficiary',                    COUNT(*),              138556            FROM gold.dim_beneficiary
UNION ALL
SELECT 'gold.dim_date',                           COUNT(*),              426               FROM gold.dim_date
UNION ALL
SELECT 'gold.dim_geography',                      COUNT(*),              52                FROM gold.dim_geography
UNION ALL
SELECT 'gold.fact_claims',                        COUNT(*),              558211            FROM gold.fact_claims
UNION ALL
SELECT 'gold.agg_provider_summary',               COUNT(*),              5410              FROM gold.agg_provider_summary
UNION ALL
SELECT 'gold.agg_state_monthly',                  COUNT(*),              682               FROM gold.agg_state_monthly
UNION ALL
SELECT 'gold.agg_chronic_disease',                COUNT(*),              11                FROM gold.agg_chronic_disease;
GO

-- =====================================================
-- SECTION 2: REFERENTIAL INTEGRITY
-- =====================================================
PRINT '--- Section 2: Referential Integrity ---';

SELECT 'fact_claims: orphaned provider_key'         AS check_name, COUNT(*) AS issue_count
FROM gold.fact_claims f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_provider p WHERE p.provider_key = f.provider_key)
UNION ALL
SELECT 'fact_claims: orphaned beneficiary_key',      COUNT(*)
FROM gold.fact_claims f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_beneficiary b WHERE b.beneficiary_key = f.beneficiary_key)
UNION ALL
SELECT 'fact_claims: orphaned claim_start_date_key', COUNT(*)
FROM gold.fact_claims f
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_date d WHERE d.date_key = f.claim_start_date_key)
UNION ALL
SELECT 'fact_claims: NULL provider_key',             COUNT(*)
FROM gold.fact_claims WHERE provider_key IS NULL
UNION ALL
SELECT 'fact_claims: NULL beneficiary_key',          COUNT(*)
FROM gold.fact_claims WHERE beneficiary_key IS NULL
UNION ALL
SELECT 'fact_claims: NULL claim_start_date_key',     COUNT(*)
FROM gold.fact_claims WHERE claim_start_date_key IS NULL;
GO

-- =====================================================
-- SECTION 3: FACT TABLE COMPLETENESS
-- =====================================================
PRINT '--- Section 3: Fact Table Completeness ---';

SELECT 'fact_claims: invalid claim_type'        AS check_name, COUNT(*) AS issue_count
FROM gold.fact_claims
WHERE claim_type NOT IN ('Inpatient', 'Outpatient')
UNION ALL
SELECT 'fact_claims: NULL claim_type',           COUNT(*)
FROM gold.fact_claims WHERE claim_type IS NULL
UNION ALL
SELECT 'fact_claims: NULL is_potential_fraud',   COUNT(*)
FROM gold.fact_claims WHERE is_potential_fraud IS NULL
UNION ALL
SELECT 'fact_claims: NULL claim_reimbursement',  COUNT(*)
FROM gold.fact_claims WHERE claim_reimbursement_amt IS NULL;
GO

SELECT claim_type, COUNT(*) AS row_count
FROM gold.fact_claims
GROUP BY claim_type;
GO

-- =====================================================
-- SECTION 4: DIMENSION TABLE INTEGRITY
-- =====================================================
PRINT '--- Section 4: Dimension Table Integrity ---';

SELECT 'dim_provider: is_potential_fraud outside 0/1' AS check_name, COUNT(*) AS issue_count
FROM gold.dim_provider WHERE is_potential_fraud NOT IN (0,1)
UNION ALL
SELECT 'dim_provider: fraud_label not Fraud/Not Fraud', COUNT(*)
FROM gold.dim_provider WHERE fraud_label NOT IN ('Fraud', 'Not Fraud')
UNION ALL
SELECT 'dim_beneficiary: NULL patient_age', COUNT(*)
FROM gold.dim_beneficiary WHERE patient_age IS NULL
UNION ALL
SELECT 'dim_beneficiary: NULL age_group', COUNT(*)
FROM gold.dim_beneficiary WHERE age_group IS NULL
UNION ALL
SELECT 'dim_geography: NULL state_name', COUNT(*)
FROM gold.dim_geography WHERE state_name IS NULL
UNION ALL
SELECT 'dim_date: NULL year_month', COUNT(*)
FROM gold.dim_date WHERE year_month IS NULL;
GO

-- =====================================================
-- SECTION 5: AGGREGATION ACCURACY
-- Verify agg tables match fact table totals
-- =====================================================
PRINT '--- Section 5: Aggregation Accuracy ---';

SELECT
    'fact_claims total reimbursement'          AS source,
    SUM(CAST(claim_reimbursement_amt AS BIGINT)) AS total_reimbursement
FROM gold.fact_claims
UNION ALL
SELECT
    'agg_provider_summary total reimbursement',
    SUM(total_reimbursement)
FROM gold.agg_provider_summary;
GO

SELECT
    'fact_claims total rows'            AS source,
    COUNT(*)                            AS total_claims
FROM gold.fact_claims
UNION ALL
SELECT
    'agg_provider_summary total claims',
    SUM(total_claims)
FROM gold.agg_provider_summary;
GO

-- =====================================================
-- SECTION 6: BUSINESS KPI VALIDATION
-- =====================================================
PRINT '--- Section 6: Business KPI Validation ---';

SELECT
    'Fraud provider rate %' AS metric,
    CAST(SUM(CAST(is_potential_fraud AS INT)) AS FLOAT) /
    COUNT(*) * 100 AS value
FROM gold.dim_provider;
GO

SELECT
    claim_type,
    COUNT(*)                                        AS claim_count,
    SUM(CAST(claim_reimbursement_amt AS BIGINT))    AS total_reimbursement,
    AVG(CAST(claim_reimbursement_amt AS FLOAT))     AS avg_reimbursement
FROM gold.fact_claims
GROUP BY claim_type;
GO

SELECT
    age_group,
    COUNT(*)                                          AS beneficiary_count,
    CAST(COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER() AS DECIMAL(5,2))         AS pct
FROM gold.dim_beneficiary
GROUP BY age_group
ORDER BY age_group;
GO

SELECT
    region,
    COUNT(DISTINCT state_code) AS state_count
FROM gold.dim_geography
WHERE region != 'Unknown'
GROUP BY region
ORDER BY region;
GO

SELECT
    MIN(full_date) AS earliest_date,
    MAX(full_date) AS latest_date,
    COUNT(*)       AS total_days
FROM gold.dim_date;
GO

-- =====================================================
-- SECTION 7: AGGREGATE TABLE SPOT CHECKS
-- =====================================================
PRINT '--- Section 7: Aggregate Table Spot Checks ---';

SELECT TOP 5
    provider_id,
    fraud_label,
    total_claims,
    total_reimbursement,
    avg_reimbursement_per_claim,
    deceased_patient_claims
FROM gold.agg_provider_summary
ORDER BY total_reimbursement DESC;
GO

SELECT TOP 5
    state_name,
    region,
    SUM(total_reimbursement) AS total_reimbursement,
    SUM(total_claims)        AS total_claims
FROM gold.agg_state_monthly
GROUP BY state_name, region
ORDER BY total_reimbursement DESC;
GO

SELECT
    disease_name,
    total_beneficiaries,
    pct_of_all_beneficiaries,
    total_reimbursement,
    avg_reimbursement_per_patient
FROM gold.agg_chronic_disease
ORDER BY total_beneficiaries DESC;
GO

PRINT '--- Gold validation complete ---';
GO
