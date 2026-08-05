/* ============================================================
   FILE: 01_bronze_create_tables.sql
   PURPOSE: Create Bronze layer tables - structure matches the
            raw source CSVs exactly. Loose typing (VARCHAR) on
            purpose so BULK INSERT never fails on a "bad" row.
   RUN FREQUENCY: ONCE, or whenever source schema changes.
                  Safe to re-run (DROP TABLE IF EXISTS first).
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- BRONZE: raw_provider_labels (from Train.csv)
-- =====================================================
DROP TABLE IF EXISTS bronze.raw_provider_labels;
GO

CREATE TABLE bronze.raw_provider_labels (
    Provider              VARCHAR(50),
    PotentialFraud         VARCHAR(10),

    -- Metadata columns (added by us, not present in source file)
    ingestion_timestamp    DATETIME2 DEFAULT SYSDATETIME(),
    source_file_name       VARCHAR(255) NULL,
    batch_id               VARCHAR(50)  NULL
);
GO

-- =====================================================
-- BRONZE: raw_inpatient (from Train_Inpatientdata.csv)
-- =====================================================
DROP TABLE IF EXISTS bronze.raw_inpatient;
GO

CREATE TABLE bronze.raw_inpatient (
    BeneID                    VARCHAR(50),
    ClaimID                   VARCHAR(50),
    ClaimStartDt               VARCHAR(20),
    ClaimEndDt                 VARCHAR(20),
    Provider                   VARCHAR(50),
    InscClaimAmtReimbursed     VARCHAR(20),
    AttendingPhysician         VARCHAR(50),
    OperatingPhysician         VARCHAR(50),
    OtherPhysician             VARCHAR(50),
    AdmissionDt                VARCHAR(20),
    ClmAdmitDiagnosisCode      VARCHAR(20),
    DeductibleAmtPaid          VARCHAR(20),
    DischargeDt                 VARCHAR(20),
    DiagnosisGroupCode         VARCHAR(20),
    ClmDiagnosisCode_1         VARCHAR(20),
    ClmDiagnosisCode_2         VARCHAR(20),
    ClmDiagnosisCode_3         VARCHAR(20),
    ClmDiagnosisCode_4         VARCHAR(20),
    ClmDiagnosisCode_5         VARCHAR(20),
    ClmDiagnosisCode_6         VARCHAR(20),
    ClmDiagnosisCode_7         VARCHAR(20),
    ClmDiagnosisCode_8         VARCHAR(20),
    ClmDiagnosisCode_9         VARCHAR(20),
    ClmDiagnosisCode_10        VARCHAR(20),
    ClmProcedureCode_1         VARCHAR(20),
    ClmProcedureCode_2         VARCHAR(20),
    ClmProcedureCode_3         VARCHAR(20),
    ClmProcedureCode_4         VARCHAR(20),
    ClmProcedureCode_5         VARCHAR(20),
    ClmProcedureCode_6         VARCHAR(20),

    -- Metadata
    ingestion_timestamp         DATETIME2 DEFAULT SYSDATETIME(),
    source_file_name            VARCHAR(255) NULL,
    batch_id                    VARCHAR(50)  NULL
);
GO

-- =====================================================
-- BRONZE: raw_outpatient (from Train_Outpatientdata.csv)
-- =====================================================
DROP TABLE IF EXISTS bronze.raw_outpatient;
GO

CREATE TABLE bronze.raw_outpatient (
    BeneID                    VARCHAR(50),
    ClaimID                   VARCHAR(50),
    ClaimStartDt               VARCHAR(20),
    ClaimEndDt                 VARCHAR(20),
    Provider                   VARCHAR(50),
    InscClaimAmtReimbursed     VARCHAR(20),
    AttendingPhysician         VARCHAR(50),
    OperatingPhysician         VARCHAR(50),
    OtherPhysician             VARCHAR(50),
    ClmDiagnosisCode_1         VARCHAR(20),
    ClmDiagnosisCode_2         VARCHAR(20),
    ClmDiagnosisCode_3         VARCHAR(20),
    ClmDiagnosisCode_4         VARCHAR(20),
    ClmDiagnosisCode_5         VARCHAR(20),
    ClmDiagnosisCode_6         VARCHAR(20),
    ClmDiagnosisCode_7         VARCHAR(20),
    ClmDiagnosisCode_8         VARCHAR(20),
    ClmDiagnosisCode_9         VARCHAR(20),
    ClmDiagnosisCode_10        VARCHAR(20),
    ClmProcedureCode_1         VARCHAR(20),
    ClmProcedureCode_2         VARCHAR(20),
    ClmProcedureCode_3         VARCHAR(20),
    ClmProcedureCode_4         VARCHAR(20),
    ClmProcedureCode_5         VARCHAR(20),
    ClmProcedureCode_6         VARCHAR(20),
    ClmAdmitDiagnosisCode      VARCHAR(20),
    DeductibleAmtPaid          VARCHAR(20),

    -- Metadata
    ingestion_timestamp         DATETIME2 DEFAULT SYSDATETIME(),
    source_file_name            VARCHAR(255) NULL,
    batch_id                    VARCHAR(50)  NULL
);
GO

-- =====================================================
-- BRONZE: raw_beneficiary (from Train_Beneficiarydata.csv)
-- =====================================================
DROP TABLE IF EXISTS bronze.raw_beneficiary;
GO

CREATE TABLE bronze.raw_beneficiary (
    BeneID                            VARCHAR(50),
    DOB                                VARCHAR(20),
    DOD                                VARCHAR(20),
    Gender                             VARCHAR(5),
    Race                               VARCHAR(5),
    RenalDiseaseIndicator              VARCHAR(5),
    State                              VARCHAR(5),
    County                             VARCHAR(5),
    NoOfMonths_PartACov                 VARCHAR(5),
    NoOfMonths_PartBCov                 VARCHAR(5),
    ChronicCond_Alzheimer               VARCHAR(5),
    ChronicCond_Heartfailure            VARCHAR(5),
    ChronicCond_KidneyDisease           VARCHAR(5),
    ChronicCond_Cancer                  VARCHAR(5),
    ChronicCond_ObstrPulmonary          VARCHAR(5),
    ChronicCond_Depression              VARCHAR(5),
    ChronicCond_Diabetes                VARCHAR(5),
    ChronicCond_IschemicHeart           VARCHAR(5),
    ChronicCond_Osteoporasis            VARCHAR(5),
    ChronicCond_rheumatoidarthritis     VARCHAR(5),
    ChronicCond_stroke                  VARCHAR(5),
    IPAnnualReimbursementAmt            VARCHAR(20),
    IPAnnualDeductibleAmt               VARCHAR(20),
    OPAnnualReimbursementAmt            VARCHAR(20),
    OPAnnualDeductibleAmt               VARCHAR(20),

    -- Metadata
    ingestion_timestamp                  DATETIME2 DEFAULT SYSDATETIME(),
    source_file_name                     VARCHAR(255) NULL,
    batch_id                             VARCHAR(50)  NULL
);
GO

PRINT 'Bronze tables created successfully.';
GO
