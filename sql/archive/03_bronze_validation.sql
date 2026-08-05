/* ============================================================
   FILE: 03_bronze_validation.sql
   PURPOSE: Sanity-check row counts after every Bronze load.
            Stop and investigate before moving to Silver if
            these don't match expectations.
   RUN FREQUENCY: AFTER every run of 02_bronze_load_data.sql
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- Row count check vs expected source file counts
-- =====================================================
SELECT 'raw_provider_labels' AS table_name, COUNT(*) AS row_count, 5410 AS expected_count FROM bronze.raw_provider_labels
UNION ALL
SELECT 'raw_inpatient', COUNT(*), 40474 FROM bronze.raw_inpatient
UNION ALL
SELECT 'raw_outpatient', COUNT(*), 517737 FROM bronze.raw_outpatient
UNION ALL
SELECT 'raw_beneficiary', COUNT(*), 138556 FROM bronze.raw_beneficiary;
GO

-- =====================================================
-- Quick peek: latest batch loaded per table
-- =====================================================
SELECT TOP 5 * FROM bronze.raw_provider_labels ORDER BY ingestion_timestamp DESC;
SELECT TOP 5 * FROM bronze.raw_inpatient ORDER BY ingestion_timestamp DESC;
SELECT TOP 5 * FROM bronze.raw_outpatient ORDER BY ingestion_timestamp DESC;
SELECT TOP 5 * FROM bronze.raw_beneficiary ORDER BY ingestion_timestamp DESC;
GO

-- =====================================================
-- Check for stray double-quote characters left in any
-- VARCHAR column (source files had inconsistent quoting)
-- =====================================================
SELECT 'raw_provider_labels.Provider' AS col, COUNT(*) AS rows_with_quote
FROM bronze.raw_provider_labels WHERE Provider LIKE '%"%'
UNION ALL
SELECT 'raw_provider_labels.PotentialFraud', COUNT(*)
FROM bronze.raw_provider_labels WHERE PotentialFraud LIKE '%"%'
UNION ALL
SELECT 'raw_inpatient.BeneID', COUNT(*)
FROM bronze.raw_inpatient WHERE BeneID LIKE '%"%'
UNION ALL
SELECT 'raw_inpatient.ClaimID', COUNT(*)
FROM bronze.raw_inpatient WHERE ClaimID LIKE '%"%'
UNION ALL
SELECT 'raw_inpatient.Provider', COUNT(*)
FROM bronze.raw_inpatient WHERE Provider LIKE '%"%'
UNION ALL
SELECT 'raw_outpatient.BeneID', COUNT(*)
FROM bronze.raw_outpatient WHERE BeneID LIKE '%"%'
UNION ALL
SELECT 'raw_outpatient.ClaimID', COUNT(*)
FROM bronze.raw_outpatient WHERE ClaimID LIKE '%"%'
UNION ALL
SELECT 'raw_outpatient.Provider', COUNT(*)
FROM bronze.raw_outpatient WHERE Provider LIKE '%"%'
UNION ALL
SELECT 'raw_beneficiary.BeneID', COUNT(*)
FROM bronze.raw_beneficiary WHERE BeneID LIKE '%"%'
UNION ALL
SELECT 'raw_beneficiary.RenalDiseaseIndicator', COUNT(*)
FROM bronze.raw_beneficiary WHERE RenalDiseaseIndicator LIKE '%"%';
GO
-- Any row_count > 0 above means quotes leaked through and
-- need cleanup (apply the same REPLACE pattern used for
-- raw_beneficiary in 02_bronze_load_data.sql to that column).

-- =====================================================
-- Check for completely blank/garbage rows (common BULK INSERT issue)
-- =====================================================
SELECT COUNT(*) AS blank_provider_rows
FROM bronze.raw_provider_labels
WHERE Provider IS NULL AND PotentialFraud IS NULL;

SELECT COUNT(*) AS blank_inpatient_rows
FROM bronze.raw_inpatient
WHERE BeneID IS NULL AND ClaimID IS NULL;

SELECT COUNT(*) AS blank_outpatient_rows
FROM bronze.raw_outpatient
WHERE BeneID IS NULL AND ClaimID IS NULL;

SELECT COUNT(*) AS blank_beneficiary_rows
FROM bronze.raw_beneficiary
WHERE BeneID IS NULL;
GO
