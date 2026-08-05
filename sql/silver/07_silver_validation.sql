/* ============================================================
   FILE: 07_silver_validation.sql
   PURPOSE: Comprehensive validation of Silver layer data after
            loading. Verifies data types, derived column logic,
            business rules, referential integrity, ranges,
            NA cleanup, and completeness.
            This is the Silver sign-off gate before Gold build.

   RUN FREQUENCY: After every run of silver.load_silver.
   NOTE: Read-only. Does not modify any data.
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- SECTION 1: ROW COUNT VERIFICATION
-- =====================================================
PRINT '--- Section 1: Row count verification ---';

SELECT 'silver.stg_provider'       AS table_name, COUNT(*) AS row_count, 5410   AS expected FROM silver.stg_provider
UNION ALL
SELECT 'silver.stg_beneficiary',                   COUNT(*),              138556            FROM silver.stg_beneficiary
UNION ALL
SELECT 'silver.stg_claims (total)', COUNT(*),                             558211            FROM silver.stg_claims
UNION ALL
SELECT 'silver.stg_claims (Inpatient)',  COUNT(*),                        40474             FROM silver.stg_claims WHERE claim_type = 'Inpatient'
UNION ALL
SELECT 'silver.stg_claims (Outpatient)', COUNT(*),                        517737            FROM silver.stg_claims WHERE claim_type = 'Outpatient';
GO

-- =====================================================
-- SECTION 2: NULL CHECKS ON CRITICAL COLUMNS
-- Silver has stricter null rules than Bronze
-- =====================================================
PRINT '--- Section 2: Null checks on critical columns ---';

SELECT 'stg_provider: provider_id NULL'        AS check_name, COUNT(*) AS issue_count FROM silver.stg_provider    WHERE provider_id IS NULL
UNION ALL
SELECT 'stg_provider: is_potential_fraud NULL',  COUNT(*) FROM silver.stg_provider    WHERE is_potential_fraud IS NULL
UNION ALL
SELECT 'stg_beneficiary: beneficiary_id NULL',   COUNT(*) FROM silver.stg_beneficiary WHERE beneficiary_id IS NULL
UNION ALL
SELECT 'stg_beneficiary: date_of_birth NULL',    COUNT(*) FROM silver.stg_beneficiary WHERE date_of_birth IS NULL
UNION ALL
SELECT 'stg_beneficiary: gender NULL',           COUNT(*) FROM silver.stg_beneficiary WHERE gender IS NULL
UNION ALL
SELECT 'stg_beneficiary: patient_age NULL',      COUNT(*) FROM silver.stg_beneficiary WHERE patient_age IS NULL
UNION ALL
SELECT 'stg_beneficiary: age_group NULL',        COUNT(*) FROM silver.stg_beneficiary WHERE age_group IS NULL
UNION ALL
SELECT 'stg_beneficiary: is_deceased NULL',      COUNT(*) FROM silver.stg_beneficiary WHERE is_deceased IS NULL
UNION ALL
SELECT 'stg_beneficiary: chronic_condition_count NULL', COUNT(*) FROM silver.stg_beneficiary WHERE chronic_condition_count IS NULL
UNION ALL
SELECT 'stg_claims: claim_id NULL',              COUNT(*) FROM silver.stg_claims WHERE claim_id IS NULL
UNION ALL
SELECT 'stg_claims: beneficiary_id NULL',        COUNT(*) FROM silver.stg_claims WHERE beneficiary_id IS NULL
UNION ALL
SELECT 'stg_claims: provider_id NULL',           COUNT(*) FROM silver.stg_claims WHERE provider_id IS NULL
UNION ALL
SELECT 'stg_claims: claim_type NULL',            COUNT(*) FROM silver.stg_claims WHERE claim_type IS NULL
UNION ALL
SELECT 'stg_claims: claim_start_date NULL',      COUNT(*) FROM silver.stg_claims WHERE claim_start_date IS NULL
UNION ALL
SELECT 'stg_claims: claim_end_date NULL',        COUNT(*) FROM silver.stg_claims WHERE claim_end_date IS NULL
UNION ALL
SELECT 'stg_claims: claim_reimbursement_amt NULL', COUNT(*) FROM silver.stg_claims WHERE claim_reimbursement_amt IS NULL;
GO

-- =====================================================
-- SECTION 3: DATA TYPE & VALUE VALIDATION
-- Confirm correct values exist after standardization
-- =====================================================
PRINT '--- Section 3: Data type and value validation ---';

-- is_potential_fraud should only be 0 or 1
SELECT 'stg_provider: is_potential_fraud outside 0/1' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_provider
WHERE is_potential_fraud NOT IN (0, 1);

-- Gender should only be Male or Female
SELECT 'stg_beneficiary: gender outside Male/Female', COUNT(*)
FROM silver.stg_beneficiary
WHERE gender NOT IN ('Male', 'Female');

-- age_group should only contain valid buckets
SELECT 'stg_beneficiary: age_group invalid value', COUNT(*)
FROM silver.stg_beneficiary
WHERE age_group NOT IN ('Below 45', '45-54', '55-64', '65+');

-- renal_disease_indicator should only be 0 or 1
SELECT 'stg_beneficiary: renal_disease_indicator outside 0/1', COUNT(*)
FROM silver.stg_beneficiary
WHERE renal_disease_indicator NOT IN (0, 1);

-- All chronic flags should only be 0 or 1 (recoded from 1/2)
SELECT 'stg_beneficiary: chronic flags outside 0/1', COUNT(*)
FROM silver.stg_beneficiary
WHERE has_alzheimer           NOT IN (0,1)
   OR has_heart_failure        NOT IN (0,1)
   OR has_kidney_disease       NOT IN (0,1)
   OR has_cancer               NOT IN (0,1)
   OR has_obstr_pulmonary      NOT IN (0,1)
   OR has_depression           NOT IN (0,1)
   OR has_diabetes             NOT IN (0,1)
   OR has_ischemic_heart       NOT IN (0,1)
   OR has_osteoporosis         NOT IN (0,1)
   OR has_rheumatoid_arthritis NOT IN (0,1)
   OR has_stroke               NOT IN (0,1);

-- claim_type should only be Inpatient or Outpatient
SELECT 'stg_claims: claim_type outside Inpatient/Outpatient', COUNT(*)
FROM silver.stg_claims
WHERE claim_type NOT IN ('Inpatient', 'Outpatient');

-- is_zero_reimbursement should only be 0 or 1
SELECT 'stg_claims: is_zero_reimbursement outside 0/1', COUNT(*)
FROM silver.stg_claims
WHERE is_zero_reimbursement NOT IN (0, 1);
GO

-- Show actual distinct values for key standardized columns
PRINT '--- Distinct values check ---';
SELECT DISTINCT is_potential_fraud FROM silver.stg_provider;
SELECT DISTINCT gender             FROM silver.stg_beneficiary;
SELECT DISTINCT age_group          FROM silver.stg_beneficiary ORDER BY 1;
SELECT DISTINCT claim_type         FROM silver.stg_claims;
SELECT DISTINCT is_deceased        FROM silver.stg_beneficiary;
GO

-- =====================================================
-- SECTION 4: DERIVED COLUMN LOGIC VERIFICATION
-- Confirm derived columns match their source logic
-- =====================================================
PRINT '--- Section 4: Derived column logic verification ---';

-- age_group must match patient_age bucket
SELECT 'stg_beneficiary: age_group does not match patient_age' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_beneficiary
WHERE (patient_age < 45 AND age_group != 'Below 45')
   OR (patient_age >= 45 AND patient_age < 55 AND age_group != '45-54')
   OR (patient_age >= 55 AND patient_age < 65 AND age_group != '55-64')
   OR (patient_age >= 65 AND age_group != '65+');

-- is_deceased must match date_of_death
SELECT 'stg_beneficiary: is_deceased does not match date_of_death', COUNT(*)
FROM silver.stg_beneficiary
WHERE (is_deceased = 1 AND date_of_death IS NULL)
   OR (is_deceased = 0 AND date_of_death IS NOT NULL);

-- chronic_condition_count must match sum of individual flags
SELECT 'stg_beneficiary: chronic_condition_count does not match flag sum', COUNT(*)
FROM silver.stg_beneficiary
WHERE chronic_condition_count != (
    has_alzheimer + has_heart_failure + has_kidney_disease +
    has_cancer + has_obstr_pulmonary + has_depression +
    has_diabetes + has_ischemic_heart + has_osteoporosis +
    has_rheumatoid_arthritis + has_stroke
);

-- claim_duration_days must match date difference
SELECT 'stg_claims: claim_duration_days does not match date diff', COUNT(*)
FROM silver.stg_claims
WHERE claim_duration_days != DATEDIFF(DAY, claim_start_date, claim_end_date);

-- admission_duration_days must match date diff for Inpatient
SELECT 'stg_claims: admission_duration_days does not match date diff (IP)', COUNT(*)
FROM silver.stg_claims
WHERE claim_type = 'Inpatient'
  AND admission_date IS NOT NULL
  AND discharge_date IS NOT NULL
  AND admission_duration_days != DATEDIFF(DAY, admission_date, discharge_date);

-- is_zero_reimbursement must match actual amount
SELECT 'stg_claims: is_zero_reimbursement flag incorrect', COUNT(*)
FROM silver.stg_claims
WHERE (is_zero_reimbursement = 1 AND claim_reimbursement_amt != 0)
   OR (is_zero_reimbursement = 0 AND claim_reimbursement_amt  = 0);

-- is_same_day_discharge must match admission = discharge for Inpatient
SELECT 'stg_claims: is_same_day_discharge flag incorrect (IP)', COUNT(*)
FROM silver.stg_claims
WHERE claim_type = 'Inpatient'
  AND admission_date IS NOT NULL
  AND discharge_date IS NOT NULL
  AND is_same_day_discharge != CASE WHEN admission_date = discharge_date THEN 1 ELSE 0 END;

-- Outpatient should have NULL for admission/discharge/same_day
SELECT 'stg_claims: Outpatient has non-NULL admission_date', COUNT(*)
FROM silver.stg_claims WHERE claim_type = 'Outpatient' AND admission_date IS NOT NULL
UNION ALL
SELECT 'stg_claims: Outpatient has non-NULL is_same_day_discharge', COUNT(*)
FROM silver.stg_claims WHERE claim_type = 'Outpatient' AND is_same_day_discharge IS NOT NULL;
GO

-- =====================================================
-- SECTION 5: REFERENTIAL INTEGRITY
-- Every claim must link to a valid beneficiary and provider
-- =====================================================
PRINT '--- Section 5: Referential integrity ---';

SELECT 'stg_claims: beneficiary_id not in stg_beneficiary' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_claims c
WHERE NOT EXISTS (
    SELECT 1 FROM silver.stg_beneficiary b
    WHERE b.beneficiary_id = c.beneficiary_id
)
UNION ALL
SELECT 'stg_claims: provider_id not in stg_provider', COUNT(*)
FROM silver.stg_claims c
WHERE NOT EXISTS (
    SELECT 1 FROM silver.stg_provider p
    WHERE p.provider_id = c.provider_id
);
GO

-- =====================================================
-- SECTION 6: NA CLEANUP VERIFICATION
-- Confirm no 'NA' strings remain anywhere in Silver
-- =====================================================
PRINT '--- Section 6: NA cleanup verification ---';

SELECT 'stg_claims: attending_physician_id = NA'  AS check_name, COUNT(*) AS issue_count
FROM silver.stg_claims WHERE attending_physician_id = 'NA'
UNION ALL
SELECT 'stg_claims: operating_physician_id = NA',  COUNT(*)
FROM silver.stg_claims WHERE operating_physician_id = 'NA'
UNION ALL
SELECT 'stg_claims: other_physician_id = NA',      COUNT(*)
FROM silver.stg_claims WHERE other_physician_id = 'NA'
UNION ALL
SELECT 'stg_claims: diagnosis_code_1 = NA',        COUNT(*)
FROM silver.stg_claims WHERE diagnosis_code_1 = 'NA'
UNION ALL
SELECT 'stg_claims: procedure_code_1 = NA',        COUNT(*)
FROM silver.stg_claims WHERE procedure_code_1 = 'NA'
UNION ALL
SELECT 'stg_beneficiary: date_of_death = NA',      COUNT(*)
FROM silver.stg_beneficiary WHERE CAST(date_of_death AS VARCHAR) = 'NA'
UNION ALL
SELECT 'stg_claims: deductible_amt_paid = NA (as text)', COUNT(*)
FROM silver.stg_claims WHERE CAST(deductible_amt_paid AS VARCHAR(50)) = 'NA';
GO

-- =====================================================
-- SECTION 7: RANGE & OUTLIER CHECKS
-- =====================================================
PRINT '--- Section 7: Range and outlier checks ---';

-- Patient age range (confirmed 26-100 from profiling)
SELECT
    'stg_beneficiary age range' AS metric,
    MIN(patient_age) AS min_val,
    MAX(patient_age) AS max_val,
    AVG(CAST(patient_age AS FLOAT)) AS avg_val
FROM silver.stg_beneficiary;

-- Any negative ages?
SELECT 'stg_beneficiary: negative patient_age' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_beneficiary WHERE patient_age < 0;

-- Claim duration range (confirmed 0-36 from profiling)
SELECT
    'stg_claims IP duration range' AS metric,
    MIN(claim_duration_days) AS min_val,
    MAX(claim_duration_days) AS max_val,
    AVG(CAST(claim_duration_days AS FLOAT)) AS avg_val
FROM silver.stg_claims WHERE claim_type = 'Inpatient';

-- Any negative durations?
SELECT 'stg_claims: negative claim_duration_days' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_claims WHERE claim_duration_days < 0;

-- Reimbursement range
SELECT
    'stg_claims IP reimbursement range' AS metric,
    MIN(claim_reimbursement_amt) AS min_val,
    MAX(claim_reimbursement_amt) AS max_val,
    AVG(CAST(claim_reimbursement_amt AS FLOAT)) AS avg_val
FROM silver.stg_claims WHERE claim_type = 'Inpatient';

SELECT
    'stg_claims OP reimbursement range' AS metric,
    MIN(claim_reimbursement_amt) AS min_val,
    MAX(claim_reimbursement_amt) AS max_val,
    AVG(CAST(claim_reimbursement_amt AS FLOAT)) AS avg_val
FROM silver.stg_claims WHERE claim_type = 'Outpatient';

-- Chronic condition count range (should be 0-11)
SELECT 'stg_beneficiary: chronic_condition_count outside 0-11' AS check_name, COUNT(*) AS issue_count
FROM silver.stg_beneficiary WHERE chronic_condition_count < 0 OR chronic_condition_count > 11;
GO

-- =====================================================
-- SECTION 8: BUSINESS LOGIC CHECKS
-- =====================================================
PRINT '--- Section 8: Business logic checks ---';

-- Fraud provider rate (should be ~9.4% from profiling)
SELECT
    'Fraud provider rate %' AS metric,
    CAST(SUM(CAST(is_potential_fraud AS INT)) AS FLOAT) /
    COUNT(*) * 100 AS value
FROM silver.stg_provider;

-- Deceased beneficiary count (should be ~1% from profiling)
SELECT
    'Deceased beneficiary %' AS metric,
    CAST(SUM(CAST(is_deceased AS INT)) AS FLOAT) /
    COUNT(*) * 100 AS value
FROM silver.stg_beneficiary;

-- Same-day discharge count (confirmed 605 from profiling)
SELECT
    'Same-day discharge count (IP)' AS metric,
    SUM(CAST(is_same_day_discharge AS INT)) AS value
FROM silver.stg_claims
WHERE claim_type = 'Inpatient';

-- Zero reimbursement count (confirmed 1085 IP + 19568 OP)
SELECT
    'Zero reimbursement count (IP)' AS metric,
    SUM(CAST(is_zero_reimbursement AS INT)) AS value
FROM silver.stg_claims WHERE claim_type = 'Inpatient'
UNION ALL
SELECT
    'Zero reimbursement count (OP)',
    SUM(CAST(is_zero_reimbursement AS INT))
FROM silver.stg_claims WHERE claim_type = 'Outpatient';

-- Age group distribution
SELECT age_group, COUNT(*) AS beneficiary_count,
       CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS pct
FROM silver.stg_beneficiary
GROUP BY age_group
ORDER BY age_group;
GO

PRINT '--- Silver validation complete. All sections done. ---';
GO
