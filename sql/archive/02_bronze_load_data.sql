/* ============================================================
   FILE: 02_bronze_load_data.sql
   PURPOSE: Stored procedure to load Bronze layer from staging
            tables created by SSMS Import Flat File Wizard.

   WHY STORED PROCEDURE:
   BULK INSERT proved unreliable in this environment due to
   the source files using inconsistent CSV quoting patterns.
   The reliable solution is the SSMS Import Flat File Wizard,
   which creates _staging tables. This stored procedure then
   copies that data into the real, properly-structured Bronze
   tables with audit metadata (source_file_name, batch_id).

   PRE-REQUISITE - Run SSMS Import Flat File Wizard 4 times
   BEFORE executing this procedure, creating these tables
   (schema = bronze, ALL columns nvarchar(50), Allow Nulls ON):
       bronze.raw_provider_labels_staging
       bronze.raw_inpatient_staging
       bronze.raw_beneficiary_staging
       bronze.raw_outpatient_staging

   USAGE:
       EXEC bronze.load_bronze;
   ============================================================ */

USE MediSight;
GO

CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
    DECLARE @start_time       DATETIME,
            @end_time         DATETIME,
            @batch_start_time DATETIME,
            @batch_end_time   DATETIME,
            @batch_id         VARCHAR(50);

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        SET @batch_id = CONVERT(VARCHAR(20), GETDATE(), 112) + '_' +
                        CONVERT(VARCHAR(10), DATEPART(HOUR,   GETDATE())) +
                        CONVERT(VARCHAR(10), DATEPART(MINUTE, GETDATE()));

        PRINT '================================================';
        PRINT 'Loading Bronze Layer';
        PRINT '================================================';
        PRINT 'Batch ID: ' + @batch_id;

        -- -----------------------------------------------
        -- TABLE 1: bronze.raw_provider_labels
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.raw_provider_labels';
        TRUNCATE TABLE bronze.raw_provider_labels;

        PRINT '>> Inserting Data Into: bronze.raw_provider_labels';
        INSERT INTO bronze.raw_provider_labels (
            Provider,
            PotentialFraud,
            source_file_name,
            batch_id
        )
        SELECT
            Provider,
            PotentialFraud,
            'Train-1542865627584.csv',
            @batch_id
        FROM bronze.raw_provider_labels_staging;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 2: bronze.raw_inpatient
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.raw_inpatient';
        TRUNCATE TABLE bronze.raw_inpatient;

        PRINT '>> Inserting Data Into: bronze.raw_inpatient';
        INSERT INTO bronze.raw_inpatient (
            BeneID, ClaimID, ClaimStartDt, ClaimEndDt, Provider,
            InscClaimAmtReimbursed, AttendingPhysician, OperatingPhysician,
            OtherPhysician, AdmissionDt, ClmAdmitDiagnosisCode, DeductibleAmtPaid,
            DischargeDt, DiagnosisGroupCode,
            ClmDiagnosisCode_1, ClmDiagnosisCode_2, ClmDiagnosisCode_3,
            ClmDiagnosisCode_4, ClmDiagnosisCode_5, ClmDiagnosisCode_6,
            ClmDiagnosisCode_7, ClmDiagnosisCode_8, ClmDiagnosisCode_9,
            ClmDiagnosisCode_10, ClmProcedureCode_1, ClmProcedureCode_2,
            ClmProcedureCode_3, ClmProcedureCode_4, ClmProcedureCode_5,
            ClmProcedureCode_6, source_file_name, batch_id
        )
        SELECT
            BeneID, ClaimID, ClaimStartDt, ClaimEndDt, Provider,
            InscClaimAmtReimbursed, AttendingPhysician, OperatingPhysician,
            OtherPhysician, AdmissionDt, ClmAdmitDiagnosisCode, DeductibleAmtPaid,
            DischargeDt, DiagnosisGroupCode,
            ClmDiagnosisCode_1, ClmDiagnosisCode_2, ClmDiagnosisCode_3,
            ClmDiagnosisCode_4, ClmDiagnosisCode_5, ClmDiagnosisCode_6,
            ClmDiagnosisCode_7, ClmDiagnosisCode_8, ClmDiagnosisCode_9,
            ClmDiagnosisCode_10, ClmProcedureCode_1, ClmProcedureCode_2,
            ClmProcedureCode_3, ClmProcedureCode_4, ClmProcedureCode_5,
            ClmProcedureCode_6,
            'Train_Inpatientdata-1542865627584.csv',
            @batch_id
        FROM bronze.raw_inpatient_staging;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 3: bronze.raw_outpatient
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.raw_outpatient';
        TRUNCATE TABLE bronze.raw_outpatient;

        PRINT '>> Inserting Data Into: bronze.raw_outpatient';
        INSERT INTO bronze.raw_outpatient (
            BeneID, ClaimID, ClaimStartDt, ClaimEndDt, Provider,
            InscClaimAmtReimbursed, AttendingPhysician, OperatingPhysician,
            OtherPhysician, ClmDiagnosisCode_1, ClmDiagnosisCode_2,
            ClmDiagnosisCode_3, ClmDiagnosisCode_4, ClmDiagnosisCode_5,
            ClmDiagnosisCode_6, ClmDiagnosisCode_7, ClmDiagnosisCode_8,
            ClmDiagnosisCode_9, ClmDiagnosisCode_10, ClmProcedureCode_1,
            ClmProcedureCode_2, ClmProcedureCode_3, ClmProcedureCode_4,
            ClmProcedureCode_5, ClmProcedureCode_6,
            ClmAdmitDiagnosisCode, DeductibleAmtPaid,
            source_file_name, batch_id
        )
        SELECT
            BeneID, ClaimID, ClaimStartDt, ClaimEndDt, Provider,
            InscClaimAmtReimbursed, AttendingPhysician, OperatingPhysician,
            OtherPhysician, ClmDiagnosisCode_1, ClmDiagnosisCode_2,
            ClmDiagnosisCode_3, ClmDiagnosisCode_4, ClmDiagnosisCode_5,
            ClmDiagnosisCode_6, ClmDiagnosisCode_7, ClmDiagnosisCode_8,
            ClmDiagnosisCode_9, ClmDiagnosisCode_10, ClmProcedureCode_1,
            ClmProcedureCode_2, ClmProcedureCode_3, ClmProcedureCode_4,
            ClmProcedureCode_5, ClmProcedureCode_6,
            ClmAdmitDiagnosisCode, DeductibleAmtPaid,
            'Train_Outpatientdata-1542865627584.csv',
            @batch_id
        FROM bronze.raw_outpatient_staging;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 4: bronze.raw_beneficiary
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: bronze.raw_beneficiary';
        TRUNCATE TABLE bronze.raw_beneficiary;

        PRINT '>> Inserting Data Into: bronze.raw_beneficiary';
        INSERT INTO bronze.raw_beneficiary (
            BeneID, DOB, DOD, Gender, Race, RenalDiseaseIndicator,
            State, County, NoOfMonths_PartACov, NoOfMonths_PartBCov,
            ChronicCond_Alzheimer, ChronicCond_Heartfailure, ChronicCond_KidneyDisease,
            ChronicCond_Cancer, ChronicCond_ObstrPulmonary, ChronicCond_Depression,
            ChronicCond_Diabetes, ChronicCond_IschemicHeart, ChronicCond_Osteoporasis,
            ChronicCond_rheumatoidarthritis, ChronicCond_stroke,
            IPAnnualReimbursementAmt, IPAnnualDeductibleAmt,
            OPAnnualReimbursementAmt, OPAnnualDeductibleAmt,
            source_file_name, batch_id
        )
        SELECT
            -- Strip stray quotes from inconsistently-quoted source fields
            REPLACE(BeneID, '"', ''),
            DOB, DOD, Gender, Race,
            REPLACE(RenalDiseaseIndicator, '"', ''),
            State, County, NoOfMonths_PartACov, NoOfMonths_PartBCov,
            ChronicCond_Alzheimer, ChronicCond_Heartfailure, ChronicCond_KidneyDisease,
            ChronicCond_Cancer, ChronicCond_ObstrPulmonary, ChronicCond_Depression,
            ChronicCond_Diabetes, ChronicCond_IschemicHeart, ChronicCond_Osteoporasis,
            ChronicCond_rheumatoidarthritis, ChronicCond_stroke,
            IPAnnualReimbursementAmt, IPAnnualDeductibleAmt,
            OPAnnualReimbursementAmt, OPAnnualDeductibleAmt,
            'Train_Beneficiarydata-1542865627584.csv',
            @batch_id
        FROM bronze.raw_beneficiary_staging;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '================================================';

    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER';
        PRINT 'Error Message: ' + ERROR_MESSAGE();
        PRINT 'Error Number:  ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State:   ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '================================================';
    END CATCH
END
GO

-- =====================================================
-- Execute the stored procedure
-- =====================================================
EXEC bronze.load_bronze;
GO

-- =====================================================
-- Verify Bronze row counts
-- =====================================================
SELECT 'bronze.raw_provider_labels' AS table_name, COUNT(*) AS row_count, 5410   AS expected FROM bronze.raw_provider_labels
UNION ALL
SELECT 'bronze.raw_inpatient',                       COUNT(*),              40474            FROM bronze.raw_inpatient
UNION ALL
SELECT 'bronze.raw_outpatient',                      COUNT(*),              517737           FROM bronze.raw_outpatient
UNION ALL
SELECT 'bronze.raw_beneficiary',                     COUNT(*),              138556           FROM bronze.raw_beneficiary;
GO
