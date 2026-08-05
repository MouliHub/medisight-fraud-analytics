/* ============================================================
   FILE: 05_silver_validation_profiling.sql
   PURPOSE: Profile Bronze data BEFORE writing Silver cleaning
            logic. This tells us what's ACTUALLY wrong with the
            data (nulls, duplicates, bad dates, out-of-range
            values) rather than assuming or guessing rules.

   RUN FREQUENCY: Run once now to inform Silver design. Re-run
   any time you want to re-check data quality after a new load.

   NOTE: This script only SELECTs - it does not modify anything.
   Safe to run repeatedly.
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- SECTION 1: NULL CHECKS ON CRITICAL JOIN KEYS
-- =====================================================
-- These columns MUST NOT be null - they're how tables connect.
-- Any null here = record can't be linked to anything = unusable.

PRINT '--- Section 1: Null checks on critical keys ---';

SELECT 'raw_provider_labels.Provider' AS check_name, COUNT(*) AS null_count
FROM bronze.raw_provider_labels WHERE Provider IS NULL
UNION ALL
SELECT 'raw_inpatient.BeneID', COUNT(*) FROM bronze.raw_inpatient WHERE BeneID IS NULL
UNION ALL
SELECT 'raw_inpatient.ClaimID', COUNT(*) FROM bronze.raw_inpatient WHERE ClaimID IS NULL
UNION ALL
SELECT 'raw_inpatient.Provider', COUNT(*) FROM bronze.raw_inpatient WHERE Provider IS NULL
UNION ALL
SELECT 'raw_outpatient.BeneID', COUNT(*) FROM bronze.raw_outpatient WHERE BeneID IS NULL
UNION ALL
SELECT 'raw_outpatient.ClaimID', COUNT(*) FROM bronze.raw_outpatient WHERE ClaimID IS NULL
UNION ALL
SELECT 'raw_outpatient.Provider', COUNT(*) FROM bronze.raw_outpatient WHERE Provider IS NULL
UNION ALL
SELECT 'raw_beneficiary.BeneID', COUNT(*) FROM bronze.raw_beneficiary WHERE BeneID IS NULL;
GO

-- =====================================================
-- SECTION 2: DUPLICATE CHECKS
-- =====================================================
-- Duplicate ClaimIDs would double-count reimbursements.
-- Duplicate BeneIDs in beneficiary table would corrupt joins.

PRINT '--- Section 2: Duplicate checks ---';

SELECT 'Duplicate ClaimID in Inpatient' AS check_name, COUNT(*) AS duplicate_groups
FROM (
    SELECT ClaimID FROM bronze.raw_inpatient
    GROUP BY ClaimID HAVING COUNT(*) > 1
) x
UNION ALL
SELECT 'Duplicate ClaimID in Outpatient', COUNT(*)
FROM (
    SELECT ClaimID FROM bronze.raw_outpatient
    GROUP BY ClaimID HAVING COUNT(*) > 1
) x
UNION ALL
SELECT 'ClaimID appearing in BOTH Inpatient and Outpatient', COUNT(*)
FROM (
    SELECT ClaimID FROM bronze.raw_inpatient
    INTERSECT
    SELECT ClaimID FROM bronze.raw_outpatient
) x
UNION ALL
SELECT 'Duplicate BeneID in Beneficiary table', COUNT(*)
FROM (
    SELECT BeneID FROM bronze.raw_beneficiary
    GROUP BY BeneID HAVING COUNT(*) > 1
) x
UNION ALL
SELECT 'Duplicate Provider in Provider Labels', COUNT(*)
FROM (
    SELECT Provider FROM bronze.raw_provider_labels
    GROUP BY Provider HAVING COUNT(*) > 1
) x;
GO

-- =====================================================
-- SECTION 3: REFERENTIAL INTEGRITY (orphaned records)
-- =====================================================
-- Claims that reference a BeneID or Provider that doesn't
-- exist in the corresponding master table.

PRINT '--- Section 3: Referential integrity ---';

SELECT 'Inpatient claims with BeneID not in Beneficiary table' AS check_name, COUNT(*) AS orphan_count
FROM bronze.raw_inpatient i
WHERE NOT EXISTS (SELECT 1 FROM bronze.raw_beneficiary b WHERE b.BeneID = i.BeneID)
UNION ALL
SELECT 'Outpatient claims with BeneID not in Beneficiary table', COUNT(*)
FROM bronze.raw_outpatient o
WHERE NOT EXISTS (SELECT 1 FROM bronze.raw_beneficiary b WHERE b.BeneID = o.BeneID)
UNION ALL
SELECT 'Inpatient claims with Provider not in Provider Labels', COUNT(*)
FROM bronze.raw_inpatient i
WHERE NOT EXISTS (SELECT 1 FROM bronze.raw_provider_labels p WHERE p.Provider = i.Provider)
UNION ALL
SELECT 'Outpatient claims with Provider not in Provider Labels', COUNT(*)
FROM bronze.raw_outpatient o
WHERE NOT EXISTS (SELECT 1 FROM bronze.raw_provider_labels p WHERE p.Provider = o.Provider);
GO

-- =====================================================
-- SECTION 4: DATE VALIDATION
-- =====================================================
-- Check date columns actually convert to valid dates, and
-- that logical date order makes sense (end >= start, etc.)

PRINT '--- Section 4: Date validation ---';

SELECT 'Inpatient: ClaimStartDt not a valid date' AS check_name, COUNT(*) AS issue_count
FROM bronze.raw_inpatient WHERE TRY_CONVERT(DATE, ClaimStartDt) IS NULL AND ClaimStartDt IS NOT NULL
UNION ALL
SELECT 'Inpatient: ClaimEndDt not a valid date', COUNT(*)
FROM bronze.raw_inpatient WHERE TRY_CONVERT(DATE, ClaimEndDt) IS NULL AND ClaimEndDt IS NOT NULL
UNION ALL
SELECT 'Inpatient: ClaimEndDt before ClaimStartDt', COUNT(*)
FROM bronze.raw_inpatient
WHERE TRY_CONVERT(DATE, ClaimEndDt) < TRY_CONVERT(DATE, ClaimStartDt)
UNION ALL
SELECT 'Inpatient: AdmissionDt not a valid date', COUNT(*)
FROM bronze.raw_inpatient WHERE TRY_CONVERT(DATE, AdmissionDt) IS NULL AND AdmissionDt IS NOT NULL
UNION ALL
SELECT 'Inpatient: DischargeDt not a valid date', COUNT(*)
FROM bronze.raw_inpatient WHERE TRY_CONVERT(DATE, DischargeDt) IS NULL AND DischargeDt IS NOT NULL
UNION ALL
SELECT 'Inpatient: DischargeDt before AdmissionDt', COUNT(*)
FROM bronze.raw_inpatient
WHERE TRY_CONVERT(DATE, DischargeDt) < TRY_CONVERT(DATE, AdmissionDt)
UNION ALL
SELECT 'Outpatient: ClaimStartDt not a valid date', COUNT(*)
FROM bronze.raw_outpatient WHERE TRY_CONVERT(DATE, ClaimStartDt) IS NULL AND ClaimStartDt IS NOT NULL
UNION ALL
SELECT 'Outpatient: ClaimEndDt before ClaimStartDt', COUNT(*)
FROM bronze.raw_outpatient
WHERE TRY_CONVERT(DATE, ClaimEndDt) < TRY_CONVERT(DATE, ClaimStartDt)
UNION ALL
SELECT 'Beneficiary: DOB not a valid date', COUNT(*)
FROM bronze.raw_beneficiary WHERE TRY_CONVERT(DATE, DOB) IS NULL AND DOB IS NOT NULL
UNION ALL
SELECT 'Beneficiary: DOD not valid (excluding NA placeholder)', COUNT(*)
FROM bronze.raw_beneficiary
WHERE DOD <> 'NA' AND DOD IS NOT NULL AND TRY_CONVERT(DATE, DOD) IS NULL
UNION ALL
SELECT 'Beneficiary: DOD before DOB', COUNT(*)
FROM bronze.raw_beneficiary
WHERE DOD <> 'NA' AND TRY_CONVERT(DATE, DOD) < TRY_CONVERT(DATE, DOB);
GO

-- =====================================================
-- SECTION 5: NUMERIC / RANGE VALIDATION
-- =====================================================

PRINT '--- Section 5: Numeric and range validation ---';

SELECT 'Inpatient: InscClaimAmtReimbursed not numeric' AS check_name, COUNT(*) AS issue_count
FROM bronze.raw_inpatient WHERE TRY_CONVERT(INT, InscClaimAmtReimbursed) IS NULL
UNION ALL
SELECT 'Inpatient: InscClaimAmtReimbursed negative or zero', COUNT(*)
FROM bronze.raw_inpatient WHERE TRY_CONVERT(INT, InscClaimAmtReimbursed) <= 0
UNION ALL
SELECT 'Outpatient: InscClaimAmtReimbursed not numeric', COUNT(*)
FROM bronze.raw_outpatient WHERE TRY_CONVERT(INT, InscClaimAmtReimbursed) IS NULL
UNION ALL
SELECT 'Outpatient: InscClaimAmtReimbursed negative or zero', COUNT(*)
FROM bronze.raw_outpatient WHERE TRY_CONVERT(INT, InscClaimAmtReimbursed) <= 0
UNION ALL
SELECT 'Inpatient: DeductibleAmtPaid not numeric (excl NA)', COUNT(*)
FROM bronze.raw_inpatient WHERE DeductibleAmtPaid <> 'NA' AND TRY_CONVERT(FLOAT, DeductibleAmtPaid) IS NULL
UNION ALL
SELECT 'Beneficiary: Gender values present', COUNT(DISTINCT Gender)
FROM bronze.raw_beneficiary
UNION ALL
SELECT 'Beneficiary: Chronic flag values outside 1/2', COUNT(*)
FROM bronze.raw_beneficiary
WHERE ChronicCond_Alzheimer NOT IN ('1','2');
GO

-- Show the actual distinct values for a few key categorical
-- columns, so we know exactly what we're standardizing
SELECT DISTINCT PotentialFraud FROM bronze.raw_provider_labels;
SELECT DISTINCT Gender FROM bronze.raw_beneficiary;
SELECT DISTINCT RenalDiseaseIndicator FROM bronze.raw_beneficiary;
GO

-- =====================================================
-- SECTION 6: "NA" PLACEHOLDER PREVALENCE
-- =====================================================
-- Source data uses the literal text "NA" for missing values
-- in many columns. Quantify how common this is per column.

PRINT '--- Section 6: NA placeholder prevalence ---';

SELECT 'Inpatient.OperatingPhysician = NA' AS check_name, COUNT(*) AS na_count, COUNT(*) * 100.0 / (SELECT COUNT(*) FROM bronze.raw_inpatient) AS pct
FROM bronze.raw_inpatient WHERE OperatingPhysician = 'NA'
UNION ALL
SELECT 'Inpatient.OtherPhysician = NA', COUNT(*), COUNT(*) * 100.0 / (SELECT COUNT(*) FROM bronze.raw_inpatient)
FROM bronze.raw_inpatient WHERE OtherPhysician = 'NA'
UNION ALL
SELECT 'Inpatient.DeductibleAmtPaid = NA', COUNT(*), COUNT(*) * 100.0 / (SELECT COUNT(*) FROM bronze.raw_inpatient)
FROM bronze.raw_inpatient WHERE DeductibleAmtPaid = 'NA'
UNION ALL
SELECT 'Beneficiary.DOD = NA (i.e. still living)', COUNT(*), COUNT(*) * 100.0 / (SELECT COUNT(*) FROM bronze.raw_beneficiary)
FROM bronze.raw_beneficiary WHERE DOD = 'NA';
GO

-- =====================================================
-- SECTION 7: REIMBURSEMENT DISTRIBUTION
-- Dashboard relevance: Page 2 (Financial & Reimbursement)
-- Understand the shape of money flowing through the system
-- before designing financial KPIs and detecting outliers.
-- =====================================================

PRINT '--- Section 7: Reimbursement distribution ---';

SELECT
    'Inpatient Reimbursement' AS claim_type,
    MIN(TRY_CONVERT(INT, InscClaimAmtReimbursed)) AS min_amt,
    MAX(TRY_CONVERT(INT, InscClaimAmtReimbursed)) AS max_amt,
    AVG(TRY_CONVERT(FLOAT, InscClaimAmtReimbursed)) AS avg_amt,
    STDEV(TRY_CONVERT(FLOAT, InscClaimAmtReimbursed)) AS stddev_amt,
    COUNT(CASE WHEN TRY_CONVERT(INT, InscClaimAmtReimbursed) > 100000 THEN 1 END) AS claims_over_100k
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Outpatient Reimbursement',
    MIN(TRY_CONVERT(INT, InscClaimAmtReimbursed)),
    MAX(TRY_CONVERT(INT, InscClaimAmtReimbursed)),
    AVG(TRY_CONVERT(FLOAT, InscClaimAmtReimbursed)),
    STDEV(TRY_CONVERT(FLOAT, InscClaimAmtReimbursed)),
    COUNT(CASE WHEN TRY_CONVERT(INT, InscClaimAmtReimbursed) > 100000 THEN 1 END)
FROM bronze.raw_outpatient;
GO

-- =====================================================
-- SECTION 8: DATE RANGE OF DATASET
-- Dashboard relevance: Page 6 (Geographic & Trend Analysis)
-- Confirms the actual time window we're working with,
-- so our trend charts have the right date axis.
-- =====================================================

PRINT '--- Section 8: Dataset date range ---';

SELECT
    'Inpatient Claims' AS source,
    MIN(TRY_CONVERT(DATE, ClaimStartDt)) AS earliest_claim,
    MAX(TRY_CONVERT(DATE, ClaimEndDt)) AS latest_claim,
    DATEDIFF(MONTH,
        MIN(TRY_CONVERT(DATE, ClaimStartDt)),
        MAX(TRY_CONVERT(DATE, ClaimEndDt))) AS span_months
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Outpatient Claims',
    MIN(TRY_CONVERT(DATE, ClaimStartDt)),
    MAX(TRY_CONVERT(DATE, ClaimEndDt)),
    DATEDIFF(MONTH,
        MIN(TRY_CONVERT(DATE, ClaimStartDt)),
        MAX(TRY_CONVERT(DATE, ClaimEndDt)))
FROM bronze.raw_outpatient
UNION ALL
SELECT
    'Beneficiary DOB range',
    MIN(TRY_CONVERT(DATE, DOB)),
    MAX(TRY_CONVERT(DATE, DOB)),
    DATEDIFF(YEAR,
        MIN(TRY_CONVERT(DATE, DOB)),
        MAX(TRY_CONVERT(DATE, DOB)))
FROM bronze.raw_beneficiary;
GO

-- =====================================================
-- SECTION 9: CLAIM & ADMISSION DURATION SANITY
-- Dashboard relevance: Page 5 (Inpatient vs Outpatient)
-- Unusually long stays or same-day admissions are both
-- operational metrics AND fraud signals.
-- =====================================================

PRINT '--- Section 9: Claim and admission duration ---';

SELECT
    'Inpatient claim duration (days)' AS metric,
    MIN(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt))) AS min_days,
    MAX(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt))) AS max_days,
    AVG(CAST(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt)) AS FLOAT)) AS avg_days
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Inpatient admission duration (days)',
    MIN(DATEDIFF(DAY, TRY_CONVERT(DATE, AdmissionDt), TRY_CONVERT(DATE, DischargeDt))),
    MAX(DATEDIFF(DAY, TRY_CONVERT(DATE, AdmissionDt), TRY_CONVERT(DATE, DischargeDt))),
    AVG(CAST(DATEDIFF(DAY, TRY_CONVERT(DATE, AdmissionDt), TRY_CONVERT(DATE, DischargeDt)) AS FLOAT))
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Outpatient claim duration (days)',
    MIN(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt))),
    MAX(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt))),
    AVG(CAST(DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt)) AS FLOAT))
FROM bronze.raw_outpatient;

-- Same-day admission/discharge count (fraud signal)
SELECT
    'Same-day admission and discharge (IP)' AS metric,
    COUNT(*) AS count,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM bronze.raw_inpatient) AS pct_of_inpatient
FROM bronze.raw_inpatient
WHERE TRY_CONVERT(DATE, AdmissionDt) = TRY_CONVERT(DATE, DischargeDt);
GO

-- =====================================================
-- SECTION 10: BENEFICIARY AGE PROFILE
-- Dashboard relevance: Page 4 (Beneficiary & Chronic Disease)
-- Medicare is typically 65+ — understanding age distribution
-- is essential for population health analysis.
-- =====================================================

PRINT '--- Section 10: Beneficiary age profile ---';

-- Using 2009-12-31 as reference date since dataset covers 2009
SELECT
    MIN(DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31')) AS min_age,
    MAX(DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31')) AS max_age,
    AVG(CAST(DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') AS FLOAT)) AS avg_age,
    COUNT(CASE WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') < 65 THEN 1 END) AS under_65_count,
    COUNT(CASE WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') >= 65 THEN 1 END) AS over_65_count,
    COUNT(CASE WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') > 100 THEN 1 END) AS over_100_count
FROM bronze.raw_beneficiary
WHERE DOB IS NOT NULL;
GO

-- =====================================================
-- SECTION 11: DIAGNOSIS & PROCEDURE CODE COMPLETENESS
-- Dashboard relevance: Page 3 (Provider Risk)
-- Providers who consistently fill all 10 diagnosis code
-- slots may be padding claims — a key fraud signal.
-- =====================================================

PRINT '--- Section 11: Diagnosis and procedure code completeness ---';

SELECT
    'Inpatient avg diagnosis codes per claim' AS metric,
    AVG(CAST(
        (CASE WHEN ClmDiagnosisCode_1 NOT IN ('NA','') AND ClmDiagnosisCode_1 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_2 NOT IN ('NA','') AND ClmDiagnosisCode_2 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_3 NOT IN ('NA','') AND ClmDiagnosisCode_3 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_4 NOT IN ('NA','') AND ClmDiagnosisCode_4 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_5 NOT IN ('NA','') AND ClmDiagnosisCode_5 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_6 NOT IN ('NA','') AND ClmDiagnosisCode_6 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_7 NOT IN ('NA','') AND ClmDiagnosisCode_7 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_8 NOT IN ('NA','') AND ClmDiagnosisCode_8 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_9 NOT IN ('NA','') AND ClmDiagnosisCode_9 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_10 NOT IN ('NA','') AND ClmDiagnosisCode_10 IS NOT NULL THEN 1 ELSE 0 END)
    AS FLOAT)) AS avg_value
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Inpatient avg procedure codes per claim',
    AVG(CAST(
        (CASE WHEN ClmProcedureCode_1 NOT IN ('NA','') AND ClmProcedureCode_1 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmProcedureCode_2 NOT IN ('NA','') AND ClmProcedureCode_2 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmProcedureCode_3 NOT IN ('NA','') AND ClmProcedureCode_3 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmProcedureCode_4 NOT IN ('NA','') AND ClmProcedureCode_4 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmProcedureCode_5 NOT IN ('NA','') AND ClmProcedureCode_5 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmProcedureCode_6 NOT IN ('NA','') AND ClmProcedureCode_6 IS NOT NULL THEN 1 ELSE 0 END)
    AS FLOAT)) AS avg_value
FROM bronze.raw_inpatient
UNION ALL
SELECT
    'Outpatient avg diagnosis codes per claim',
    AVG(CAST(
        (CASE WHEN ClmDiagnosisCode_1 NOT IN ('NA','') AND ClmDiagnosisCode_1 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_2 NOT IN ('NA','') AND ClmDiagnosisCode_2 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_3 NOT IN ('NA','') AND ClmDiagnosisCode_3 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_4 NOT IN ('NA','') AND ClmDiagnosisCode_4 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_5 NOT IN ('NA','') AND ClmDiagnosisCode_5 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_6 NOT IN ('NA','') AND ClmDiagnosisCode_6 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_7 NOT IN ('NA','') AND ClmDiagnosisCode_7 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_8 NOT IN ('NA','') AND ClmDiagnosisCode_8 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_9 NOT IN ('NA','') AND ClmDiagnosisCode_9 IS NOT NULL THEN 1 ELSE 0 END) +
        (CASE WHEN ClmDiagnosisCode_10 NOT IN ('NA','') AND ClmDiagnosisCode_10 IS NOT NULL THEN 1 ELSE 0 END)
    AS FLOAT)) AS avg_value
FROM bronze.raw_outpatient;
GO

-- =====================================================
-- SECTION 12: PROVIDER COVERAGE CHECK
-- Dashboard relevance: Page 3 (Provider Performance & Risk)
-- Confirms every provider in claims has a fraud label,
-- and how many providers are actually active in claims.
-- =====================================================

PRINT '--- Section 12: Provider coverage ---';

SELECT
    'Total providers in label table' AS metric,
    COUNT(DISTINCT Provider) AS count
FROM bronze.raw_provider_labels
UNION ALL
SELECT 'Unique providers in Inpatient claims', COUNT(DISTINCT Provider)
FROM bronze.raw_inpatient
UNION ALL
SELECT 'Unique providers in Outpatient claims', COUNT(DISTINCT Provider)
FROM bronze.raw_outpatient
UNION ALL
SELECT 'Providers in claims but NOT in label table', COUNT(DISTINCT Provider)
FROM (
    SELECT Provider FROM bronze.raw_inpatient
    UNION
    SELECT Provider FROM bronze.raw_outpatient
) all_claim_providers
WHERE Provider NOT IN (SELECT Provider FROM bronze.raw_provider_labels)
UNION ALL
SELECT 'Fraud providers (PotentialFraud = Yes)', COUNT(*)
FROM bronze.raw_provider_labels WHERE PotentialFraud = 'Yes'
UNION ALL
SELECT 'Non-fraud providers (PotentialFraud = No)', COUNT(*)
FROM bronze.raw_provider_labels WHERE PotentialFraud = 'No';
GO

PRINT '--- Full profiling complete. All sections done. ---';
GO
