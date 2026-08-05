/* ============================================================
   FILE: 07_silver_load_data.sql
   PURPOSE: Stored procedure to load Silver layer from Bronze.
            Truncates Silver tables and re-inserts transformed,
            cleaned data. Run this any time Bronze is refreshed
            to propagate new data through to Silver automatically.

   USAGE:
       EXEC silver.load_silver;

   CLEANING RULES APPLIED:
   Provider:
     - PotentialFraud 'Yes'/'No' -> BIT 1/0

   Beneficiary:
     - DOB/DOD VARCHAR -> DATE
     - DOD 'NA' -> NULL (living patients)
     - Gender 1/2 -> 'Male'/'Female'
     - RenalDiseaseIndicator 'Y'/'0' -> TINYINT 1/0
     - Chronic flags: 1->1 (has), 2->0 (does not have)
     - Race removed (not used in any dashboard page)
     - NoOfMonths_PartACov/PartBCov removed (near-zero variance)
     - Derived: patient_age (as of 2009-12-31), age_group,
       is_deceased, chronic_condition_count

   Claims (Inpatient + Outpatient combined):
     - Dates VARCHAR -> DATE
     - InscClaimAmtReimbursed VARCHAR -> INT
     - DeductibleAmtPaid 'NA' -> 0
     - Physician 'NA' -> NULL
     - Diagnosis/Procedure codes 'NA' -> NULL
     - DiagnosisGroupCode removed (redundant)
     - ClmAdmitDiagnosisCode removed (captured in code_1)
     - Derived: claim_duration_days, admission_duration_days,
       diagnosis_code_count, procedure_code_count,
       is_zero_reimbursement, is_same_day_discharge
   ============================================================ */

USE MediSight;
GO

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time      DATETIME,
            @end_time        DATETIME,
            @batch_start_time DATETIME,
            @batch_end_time  DATETIME;

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

        -- -----------------------------------------------
        -- TABLE 1: silver.stg_provider
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.stg_provider';
        TRUNCATE TABLE silver.stg_provider;

        PRINT '>> Inserting Data Into: silver.stg_provider';
        INSERT INTO silver.stg_provider (
            provider_id,
            is_potential_fraud
        )
        SELECT
            TRIM(Provider),
            CASE
                WHEN TRIM(PotentialFraud) = 'Yes' THEN 1
                WHEN TRIM(PotentialFraud) = 'No'  THEN 0
                ELSE NULL
            END
        FROM bronze.raw_provider_labels;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 2: silver.stg_beneficiary
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.stg_beneficiary';
        TRUNCATE TABLE silver.stg_beneficiary;

        PRINT '>> Inserting Data Into: silver.stg_beneficiary';
        INSERT INTO silver.stg_beneficiary (
            beneficiary_id,
            date_of_birth,
            date_of_death,
            gender,
            renal_disease_indicator,
            state_code,
            county_code,
            has_alzheimer,
            has_heart_failure,
            has_kidney_disease,
            has_cancer,
            has_obstr_pulmonary,
            has_depression,
            has_diabetes,
            has_ischemic_heart,
            has_osteoporosis,
            has_rheumatoid_arthritis,
            has_stroke,
            ip_annual_reimbursement_amt,
            ip_annual_deductible_amt,
            op_annual_reimbursement_amt,
            op_annual_deductible_amt,
            patient_age,
            age_group,
            is_deceased,
            chronic_condition_count
        )
        SELECT
            -- Identity
            TRIM(BeneID),

            -- Dates: safe direct cast (profiling confirmed all valid)
            TRY_CONVERT(DATE, DOB),

            -- DOD: 'NA' = still living -> NULL
            CASE WHEN TRIM(DOD) = 'NA' THEN NULL
                 ELSE TRY_CONVERT(DATE, DOD)
            END,

            -- Gender: decode 1/2 to readable labels
            CASE
                WHEN TRIM(Gender) = '1' THEN 'Male'
                WHEN TRIM(Gender) = '2' THEN 'Female'
                ELSE NULL
            END,

            -- RenalDiseaseIndicator: standardize Y/0 -> 1/0
            CASE
                WHEN TRIM(RenalDiseaseIndicator) = 'Y' THEN 1
                WHEN TRIM(RenalDiseaseIndicator) = '0' THEN 0
                ELSE NULL
            END,

            -- Geography
            TRY_CONVERT(INT, State),
            TRY_CONVERT(INT, County),

            -- Chronic conditions: recode 1->1 (has), 2->0 (does not)
            CASE WHEN TRIM(ChronicCond_Alzheimer)          = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_Heartfailure)        = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_KidneyDisease)       = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_Cancer)              = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_ObstrPulmonary)      = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_Depression)          = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_Diabetes)            = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_IschemicHeart)       = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_Osteoporasis)        = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_rheumatoidarthritis) = '1' THEN 1 ELSE 0 END,
            CASE WHEN TRIM(ChronicCond_stroke)              = '1' THEN 1 ELSE 0 END,

            -- Financial
            TRY_CONVERT(INT, IPAnnualReimbursementAmt),
            TRY_CONVERT(INT, IPAnnualDeductibleAmt),
            TRY_CONVERT(INT, OPAnnualReimbursementAmt),
            TRY_CONVERT(INT, OPAnnualDeductibleAmt),

            -- DERIVED: patient_age as of 2009-12-31
            -- (dataset reference date confirmed from profiling Section 8)
            DATEDIFF(YEAR,
                TRY_CONVERT(DATE, DOB),
                '2009-12-31'),

            -- DERIVED: age_group (US healthcare analytics standard segmentation)
            -- 4-tier structure reflecting typical Medicare/commercial payer
            -- reporting: pre-Medicare population broken into working-age
            -- brackets (Below 45 / 45-54 / 55-64), with 65+ as a single
            -- Medicare-eligible tier
            CASE
                WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') < 45 THEN 'Below 45'
                WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') < 55 THEN '45-54'
                WHEN DATEDIFF(YEAR, TRY_CONVERT(DATE, DOB), '2009-12-31') < 65 THEN '55-64'
                ELSE '65+'
            END,

            -- DERIVED: is_deceased
            CASE WHEN TRIM(DOD) = 'NA' OR DOD IS NULL THEN 0 ELSE 1 END,

            -- DERIVED: chronic_condition_count (sum of all 11 recoded flags)
            (CASE WHEN TRIM(ChronicCond_Alzheimer)          = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_Heartfailure)        = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_KidneyDisease)       = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_Cancer)              = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_ObstrPulmonary)      = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_Depression)          = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_Diabetes)            = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_IschemicHeart)       = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_Osteoporasis)        = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_rheumatoidarthritis) = '1' THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ChronicCond_stroke)              = '1' THEN 1 ELSE 0 END)

        FROM bronze.raw_beneficiary;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 3: silver.stg_claims
        -- Part A: Inpatient Claims
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: silver.stg_claims';
        TRUNCATE TABLE silver.stg_claims;

        PRINT '>> Inserting Data Into: silver.stg_claims (Inpatient)';
        INSERT INTO silver.stg_claims (
            claim_id, beneficiary_id, provider_id, claim_type,
            claim_start_date, claim_end_date, admission_date, discharge_date,
            claim_reimbursement_amt, deductible_amt_paid,
            attending_physician_id, operating_physician_id, other_physician_id,
            diagnosis_code_1, diagnosis_code_2, diagnosis_code_3, diagnosis_code_4,
            diagnosis_code_5, diagnosis_code_6, diagnosis_code_7, diagnosis_code_8,
            diagnosis_code_9, diagnosis_code_10,
            procedure_code_1, procedure_code_2, procedure_code_3,
            procedure_code_4, procedure_code_5, procedure_code_6,
            claim_duration_days, admission_duration_days,
            diagnosis_code_count, procedure_code_count,
            is_zero_reimbursement, is_same_day_discharge
        )
        SELECT
            TRIM(ClaimID),
            TRIM(BeneID),
            TRIM(Provider),
            'Inpatient',

            TRY_CONVERT(DATE, ClaimStartDt),
            TRY_CONVERT(DATE, ClaimEndDt),
            TRY_CONVERT(DATE, AdmissionDt),
            TRY_CONVERT(DATE, DischargeDt),

            TRY_CONVERT(INT, InscClaimAmtReimbursed),

            CASE WHEN TRIM(DeductibleAmtPaid) = 'NA' THEN 0
                 ELSE TRY_CONVERT(DECIMAL(10,2), DeductibleAmtPaid)
            END,

            CASE WHEN TRIM(AttendingPhysician)  = 'NA' THEN NULL ELSE TRIM(AttendingPhysician)  END,
            CASE WHEN TRIM(OperatingPhysician)  = 'NA' THEN NULL ELSE TRIM(OperatingPhysician)  END,
            CASE WHEN TRIM(OtherPhysician)      = 'NA' THEN NULL ELSE TRIM(OtherPhysician)      END,

            CASE WHEN TRIM(ClmDiagnosisCode_1)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_1)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_2)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_2)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_3)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_3)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_4)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_4)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_5)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_5)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_6)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_6)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_7)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_7)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_8)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_8)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_9)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_9)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_10) = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_10) END,

            CASE WHEN TRIM(ClmProcedureCode_1)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_1)  END,
            CASE WHEN TRIM(ClmProcedureCode_2)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_2)  END,
            CASE WHEN TRIM(ClmProcedureCode_3)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_3)  END,
            CASE WHEN TRIM(ClmProcedureCode_4)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_4)  END,
            CASE WHEN TRIM(ClmProcedureCode_5)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_5)  END,
            CASE WHEN TRIM(ClmProcedureCode_6)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_6)  END,

            DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt)),
            DATEDIFF(DAY, TRY_CONVERT(DATE, AdmissionDt),  TRY_CONVERT(DATE, DischargeDt)),

            -- diagnosis_code_count
            (CASE WHEN TRIM(ClmDiagnosisCode_1)  NOT IN ('NA','') AND ClmDiagnosisCode_1  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_2)  NOT IN ('NA','') AND ClmDiagnosisCode_2  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_3)  NOT IN ('NA','') AND ClmDiagnosisCode_3  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_4)  NOT IN ('NA','') AND ClmDiagnosisCode_4  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_5)  NOT IN ('NA','') AND ClmDiagnosisCode_5  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_6)  NOT IN ('NA','') AND ClmDiagnosisCode_6  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_7)  NOT IN ('NA','') AND ClmDiagnosisCode_7  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_8)  NOT IN ('NA','') AND ClmDiagnosisCode_8  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_9)  NOT IN ('NA','') AND ClmDiagnosisCode_9  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_10) NOT IN ('NA','') AND ClmDiagnosisCode_10 IS NOT NULL THEN 1 ELSE 0 END),

            -- procedure_code_count
            (CASE WHEN TRIM(ClmProcedureCode_1) NOT IN ('NA','') AND ClmProcedureCode_1 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_2) NOT IN ('NA','') AND ClmProcedureCode_2 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_3) NOT IN ('NA','') AND ClmProcedureCode_3 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_4) NOT IN ('NA','') AND ClmProcedureCode_4 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_5) NOT IN ('NA','') AND ClmProcedureCode_5 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_6) NOT IN ('NA','') AND ClmProcedureCode_6 IS NOT NULL THEN 1 ELSE 0 END),

            CASE WHEN TRY_CONVERT(INT, InscClaimAmtReimbursed) = 0 THEN 1 ELSE 0 END,
            CASE WHEN TRY_CONVERT(DATE, AdmissionDt) = TRY_CONVERT(DATE, DischargeDt) THEN 1 ELSE 0 END

        FROM bronze.raw_inpatient;

        PRINT '>> Inserting Data Into: silver.stg_claims (Outpatient)';

        -- Part B: Outpatient Claims (appended to same table)
        INSERT INTO silver.stg_claims (
            claim_id, beneficiary_id, provider_id, claim_type,
            claim_start_date, claim_end_date, admission_date, discharge_date,
            claim_reimbursement_amt, deductible_amt_paid,
            attending_physician_id, operating_physician_id, other_physician_id,
            diagnosis_code_1, diagnosis_code_2, diagnosis_code_3, diagnosis_code_4,
            diagnosis_code_5, diagnosis_code_6, diagnosis_code_7, diagnosis_code_8,
            diagnosis_code_9, diagnosis_code_10,
            procedure_code_1, procedure_code_2, procedure_code_3,
            procedure_code_4, procedure_code_5, procedure_code_6,
            claim_duration_days, admission_duration_days,
            diagnosis_code_count, procedure_code_count,
            is_zero_reimbursement, is_same_day_discharge
        )
        SELECT
            TRIM(ClaimID),
            TRIM(BeneID),
            TRIM(Provider),
            'Outpatient',

            TRY_CONVERT(DATE, ClaimStartDt),
            TRY_CONVERT(DATE, ClaimEndDt),
            NULL,   -- no admission date for outpatient
            NULL,   -- no discharge date for outpatient

            TRY_CONVERT(INT, InscClaimAmtReimbursed),

            CASE WHEN TRIM(DeductibleAmtPaid) = 'NA' THEN 0
                 ELSE TRY_CONVERT(DECIMAL(10,2), DeductibleAmtPaid)
            END,

            CASE WHEN TRIM(AttendingPhysician)  = 'NA' THEN NULL ELSE TRIM(AttendingPhysician)  END,
            CASE WHEN TRIM(OperatingPhysician)  = 'NA' THEN NULL ELSE TRIM(OperatingPhysician)  END,
            CASE WHEN TRIM(OtherPhysician)      = 'NA' THEN NULL ELSE TRIM(OtherPhysician)      END,

            CASE WHEN TRIM(ClmDiagnosisCode_1)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_1)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_2)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_2)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_3)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_3)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_4)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_4)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_5)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_5)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_6)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_6)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_7)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_7)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_8)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_8)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_9)  = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_9)  END,
            CASE WHEN TRIM(ClmDiagnosisCode_10) = 'NA' THEN NULL ELSE TRIM(ClmDiagnosisCode_10) END,

            CASE WHEN TRIM(ClmProcedureCode_1)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_1)  END,
            CASE WHEN TRIM(ClmProcedureCode_2)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_2)  END,
            CASE WHEN TRIM(ClmProcedureCode_3)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_3)  END,
            CASE WHEN TRIM(ClmProcedureCode_4)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_4)  END,
            CASE WHEN TRIM(ClmProcedureCode_5)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_5)  END,
            CASE WHEN TRIM(ClmProcedureCode_6)  = 'NA' THEN NULL ELSE TRIM(ClmProcedureCode_6)  END,

            DATEDIFF(DAY, TRY_CONVERT(DATE, ClaimStartDt), TRY_CONVERT(DATE, ClaimEndDt)),
            NULL,   -- admission_duration_days NULL for outpatient

            (CASE WHEN TRIM(ClmDiagnosisCode_1)  NOT IN ('NA','') AND ClmDiagnosisCode_1  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_2)  NOT IN ('NA','') AND ClmDiagnosisCode_2  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_3)  NOT IN ('NA','') AND ClmDiagnosisCode_3  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_4)  NOT IN ('NA','') AND ClmDiagnosisCode_4  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_5)  NOT IN ('NA','') AND ClmDiagnosisCode_5  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_6)  NOT IN ('NA','') AND ClmDiagnosisCode_6  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_7)  NOT IN ('NA','') AND ClmDiagnosisCode_7  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_8)  NOT IN ('NA','') AND ClmDiagnosisCode_8  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_9)  NOT IN ('NA','') AND ClmDiagnosisCode_9  IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmDiagnosisCode_10) NOT IN ('NA','') AND ClmDiagnosisCode_10 IS NOT NULL THEN 1 ELSE 0 END),

            (CASE WHEN TRIM(ClmProcedureCode_1) NOT IN ('NA','') AND ClmProcedureCode_1 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_2) NOT IN ('NA','') AND ClmProcedureCode_2 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_3) NOT IN ('NA','') AND ClmProcedureCode_3 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_4) NOT IN ('NA','') AND ClmProcedureCode_4 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_5) NOT IN ('NA','') AND ClmProcedureCode_5 IS NOT NULL THEN 1 ELSE 0 END) +
            (CASE WHEN TRIM(ClmProcedureCode_6) NOT IN ('NA','') AND ClmProcedureCode_6 IS NOT NULL THEN 1 ELSE 0 END),

            CASE WHEN TRY_CONVERT(INT, InscClaimAmtReimbursed) = 0 THEN 1 ELSE 0 END,
            NULL    -- is_same_day_discharge NULL for outpatient

        FROM bronze.raw_outpatient;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '================================================';

    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER';
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
EXEC silver.load_silver;
GO

-- =====================================================
-- Verify Silver row counts
-- =====================================================
SELECT 'silver.stg_provider'          AS table_name, COUNT(*) AS row_count, 5410   AS expected FROM silver.stg_provider
UNION ALL
SELECT 'silver.stg_beneficiary',                      COUNT(*),              138556            FROM silver.stg_beneficiary
UNION ALL
SELECT 'silver.stg_claims (total)',                   COUNT(*),              558211            FROM silver.stg_claims
UNION ALL
SELECT 'silver.stg_claims (Inpatient)',               COUNT(*),              40474             FROM silver.stg_claims WHERE claim_type = 'Inpatient'
UNION ALL
SELECT 'silver.stg_claims (Outpatient)',              COUNT(*),              517737            FROM silver.stg_claims WHERE claim_type = 'Outpatient';
GO
