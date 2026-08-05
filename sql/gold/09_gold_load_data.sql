/* ============================================================
   FILE: 09_gold_load_data.sql
   PURPOSE: Stored procedure to load Gold layer from Silver.
            Populates all 8 Gold tables in correct dependency
            order (dims first, then fact, then aggregations).

   LOAD ORDER:
     1. dim_geography    (reference data - hardcoded CMS mapping)
     2. dim_date         (generated calendar - no source table)
     3. dim_provider     (from silver.stg_provider)
     4. dim_beneficiary  (from silver.stg_beneficiary)
     5. fact_claims      (from silver.stg_claims + dim lookups)
     6. agg_provider_summary  (from fact_claims + dims)
     7. agg_state_monthly     (from fact_claims + dims)
     8. agg_chronic_disease   (from silver.stg_beneficiary + fact)

   USAGE:
       EXEC gold.load_gold;
   ============================================================ */

USE MediSight;
GO

CREATE OR ALTER PROCEDURE gold.load_gold AS
BEGIN
    DECLARE @start_time       DATETIME,
            @end_time         DATETIME,
            @batch_start_time DATETIME,
            @batch_end_time   DATETIME;

    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Gold Layer';
        PRINT '================================================';

        -- -----------------------------------------------
        -- PRE-TRUNCATE: all Gold tables
        -- No physical FK constraints in Gold layer (correct
        -- data warehouse pattern - quality enforced in Silver).
        -- Truncate fact first, then dims, then agg tables.
        -- -----------------------------------------------
        PRINT '>> Truncating all Gold tables';
        TRUNCATE TABLE gold.fact_claims;
        TRUNCATE TABLE gold.agg_provider_summary;
        TRUNCATE TABLE gold.agg_state_monthly;
        TRUNCATE TABLE gold.agg_chronic_disease;
        TRUNCATE TABLE gold.dim_provider;
        TRUNCATE TABLE gold.dim_beneficiary;
        TRUNCATE TABLE gold.dim_date;
        TRUNCATE TABLE gold.dim_geography;
        PRINT '>> Truncate complete';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 1: gold.dim_geography
        -- CMS Medicare state code → state name mapping
        -- Hardcoded reference data (not in source files)
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.dim_geography';
        TRUNCATE TABLE gold.dim_geography;

        PRINT '>> Inserting Data Into: gold.dim_geography';
        INSERT INTO gold.dim_geography (state_code, state_name, state_abbr, region)
        VALUES
            (1,  'Alabama',              'AL', 'South'),
            (2,  'Alaska',               'AK', 'West'),
            (3,  'Arizona',              'AZ', 'West'),
            (4,  'Arkansas',             'AR', 'South'),
            (5,  'California',           'CA', 'West'),
            (6,  'Colorado',             'CO', 'West'),
            (7,  'Connecticut',          'CT', 'Northeast'),
            (8,  'Delaware',             'DE', 'South'),
            (9,  'District of Columbia', 'DC', 'South'),
            (10, 'Florida',              'FL', 'South'),
            (11, 'Georgia',              'GA', 'South'),
            (12, 'Hawaii',               'HI', 'West'),
            (13, 'Idaho',                'ID', 'West'),
            (14, 'Illinois',             'IL', 'Midwest'),
            (15, 'Indiana',              'IN', 'Midwest'),
            (16, 'Iowa',                 'IA', 'Midwest'),
            (17, 'Kansas',               'KS', 'Midwest'),
            (18, 'Kentucky',             'KY', 'South'),
            (19, 'Louisiana',            'LA', 'South'),
            (20, 'Maine',                'ME', 'Northeast'),
            (21, 'Maryland',             'MD', 'South'),
            (22, 'Massachusetts',        'MA', 'Northeast'),
            (23, 'Michigan',             'MI', 'Midwest'),
            (24, 'Minnesota',            'MN', 'Midwest'),
            (25, 'Mississippi',          'MS', 'South'),
            (26, 'Missouri',             'MO', 'Midwest'),
            (27, 'Montana',              'MT', 'West'),
            (28, 'Nebraska',             'NE', 'Midwest'),
            (29, 'Nevada',               'NV', 'West'),
            (30, 'New Hampshire',        'NH', 'Northeast'),
            (31, 'New Jersey',           'NJ', 'Northeast'),
            (32, 'New Mexico',           'NM', 'West'),
            (33, 'New York',             'NY', 'Northeast'),
            (34, 'North Carolina',       'NC', 'South'),
            (35, 'North Dakota',         'ND', 'Midwest'),
            (36, 'Ohio',                 'OH', 'Midwest'),
            (37, 'Oklahoma',             'OK', 'South'),
            (38, 'Oregon',               'OR', 'West'),
            (39, 'Pennsylvania',         'PA', 'Northeast'),
            (41, 'Rhode Island',         'RI', 'Northeast'),
            (42, 'South Carolina',       'SC', 'South'),
            (43, 'South Dakota',         'SD', 'Midwest'),
            (44, 'Tennessee',            'TN', 'South'),
            (45, 'Texas',                'TX', 'South'),
            (46, 'Utah',                 'UT', 'West'),
            (47, 'Vermont',              'VT', 'Northeast'),
            (49, 'Virginia',             'VA', 'South'),
            (50, 'Washington',           'WA', 'West'),
            (51, 'West Virginia',        'WV', 'South'),
            (52, 'Wisconsin',            'WI', 'Midwest'),
            (53, 'Wyoming',              'WY', 'West'),
            (54, 'Other/Unknown',        'XX', 'Unknown');

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 2: gold.dim_date
        -- Generated calendar covering dataset range
        -- 2008-11-01 to 2009-12-31 (confirmed from profiling)
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.dim_date';
        TRUNCATE TABLE gold.dim_date;

        PRINT '>> Inserting Data Into: gold.dim_date';
        WITH date_series AS (
            SELECT CAST('2008-11-01' AS DATE) AS full_date
            UNION ALL
            SELECT DATEADD(DAY, 1, full_date)
            FROM date_series
            WHERE full_date < '2009-12-31'
        )
        INSERT INTO gold.dim_date (
            date_key, full_date, day_of_month, day_name,
            week_of_year, month_num, month_name,
            quarter_num, quarter_name, year_num,
            year_month, is_weekend
        )
        SELECT
            CAST(FORMAT(full_date, 'yyyyMMdd') AS INT),
            full_date,
            DAY(full_date),
            DATENAME(WEEKDAY, full_date),
            DATEPART(WEEK, full_date),
            MONTH(full_date),
            DATENAME(MONTH, full_date),
            DATEPART(QUARTER, full_date),
            'Q' + CAST(DATEPART(QUARTER, full_date) AS VARCHAR),
            YEAR(full_date),
            FORMAT(full_date, 'yyyy-MM'),
            CASE WHEN DATEPART(WEEKDAY, full_date) IN (1,7) THEN 1 ELSE 0 END
        FROM date_series
        OPTION (MAXRECURSION 500);

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 3: gold.dim_provider
        -- Source: silver.stg_provider
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.dim_provider';
        TRUNCATE TABLE gold.dim_provider;

        PRINT '>> Inserting Data Into: gold.dim_provider';
        INSERT INTO gold.dim_provider (
            provider_id,
            is_potential_fraud,
            fraud_label
        )
        SELECT
            provider_id,
            is_potential_fraud,
            CASE WHEN is_potential_fraud = 1 THEN 'Fraud' ELSE 'Not Fraud' END
        FROM silver.stg_provider;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 4: gold.dim_beneficiary
        -- Source: silver.stg_beneficiary
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.dim_beneficiary';
        TRUNCATE TABLE gold.dim_beneficiary;

        PRINT '>> Inserting Data Into: gold.dim_beneficiary';
        INSERT INTO gold.dim_beneficiary (
            beneficiary_id, date_of_birth, date_of_death,
            gender, renal_disease_indicator, state_code, county_code,
            patient_age, age_group, is_deceased, chronic_condition_count,
            has_alzheimer, has_heart_failure, has_kidney_disease,
            has_cancer, has_obstr_pulmonary, has_depression, has_diabetes,
            has_ischemic_heart, has_osteoporosis, has_rheumatoid_arthritis,
            has_stroke, ip_annual_reimbursement_amt, ip_annual_deductible_amt,
            op_annual_reimbursement_amt, op_annual_deductible_amt
        )
        SELECT
            beneficiary_id, date_of_birth, date_of_death,
            gender, renal_disease_indicator, state_code, county_code,
            patient_age, age_group, is_deceased, chronic_condition_count,
            has_alzheimer, has_heart_failure, has_kidney_disease,
            has_cancer, has_obstr_pulmonary, has_depression, has_diabetes,
            has_ischemic_heart, has_osteoporosis, has_rheumatoid_arthritis,
            has_stroke, ip_annual_reimbursement_amt, ip_annual_deductible_amt,
            op_annual_reimbursement_amt, op_annual_deductible_amt
        FROM silver.stg_beneficiary;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 5: gold.fact_claims
        -- Source: silver.stg_claims
        -- Joins to all 4 dims to resolve surrogate keys
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.fact_claims';
        TRUNCATE TABLE gold.fact_claims;

        PRINT '>> Inserting Data Into: gold.fact_claims';
        INSERT INTO gold.fact_claims (
            claim_id,
            provider_key,
            beneficiary_key,
            claim_start_date_key,
            geo_key,
            claim_type,
            is_potential_fraud,
            claim_reimbursement_amt,
            deductible_amt_paid,
            claim_duration_days,
            admission_duration_days,
            diagnosis_code_count,
            procedure_code_count,
            is_zero_reimbursement,
            is_same_day_discharge
        )
        SELECT
            c.claim_id,

            -- Resolve provider surrogate key
            dp.provider_key,

            -- Resolve beneficiary surrogate key
            db.beneficiary_key,

            -- Resolve date surrogate key (YYYYMMDD integer)
            CAST(FORMAT(c.claim_start_date, 'yyyyMMdd') AS INT),

            -- Resolve geography surrogate key via beneficiary state
            dg.geo_key,

            -- Degenerate dimensions
            c.claim_type,
            dp.is_potential_fraud,

            -- Measures
            c.claim_reimbursement_amt,
            c.deductible_amt_paid,
            c.claim_duration_days,
            c.admission_duration_days,
            c.diagnosis_code_count,
            c.procedure_code_count,

            -- Flags
            c.is_zero_reimbursement,
            c.is_same_day_discharge

        FROM silver.stg_claims c

        -- Join to dim_provider
        INNER JOIN gold.dim_provider dp
            ON dp.provider_id = c.provider_id

        -- Join to dim_beneficiary
        INNER JOIN gold.dim_beneficiary db
            ON db.beneficiary_id = c.beneficiary_id

        -- Join to dim_geography via beneficiary state code
        LEFT JOIN gold.dim_geography dg
            ON dg.state_code = db.state_code;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 6: gold.agg_provider_summary
        -- Provider-level rollup from fact + dims
        -- Powers Pages 2 (Financial) and 3 (Provider Risk)
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.agg_provider_summary';
        TRUNCATE TABLE gold.agg_provider_summary;

        PRINT '>> Inserting Data Into: gold.agg_provider_summary';
        INSERT INTO gold.agg_provider_summary (
            provider_id, is_potential_fraud, fraud_label,
            total_claims, total_ip_claims, total_op_claims,
            total_reimbursement, avg_reimbursement_per_claim,
            max_reimbursement, total_deductible,
            unique_beneficiaries, unique_attending_physicians,
            avg_claim_duration_days, avg_admission_duration_days,
            avg_diagnosis_code_count, avg_procedure_code_count,
            zero_reimbursement_claims, same_day_discharge_claims,
            deceased_patient_claims
        )
        SELECT
            dp.provider_id,
            dp.is_potential_fraud,
            dp.fraud_label,

            COUNT(f.claim_key)                                          AS total_claims,
            SUM(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 ELSE 0 END) AS total_ip_claims,
            SUM(CASE WHEN f.claim_type = 'Outpatient' THEN 1 ELSE 0 END) AS total_op_claims,

            SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
            AVG(CAST(f.claim_reimbursement_amt AS DECIMAL(12,2)))       AS avg_reimbursement_per_claim,
            MAX(f.claim_reimbursement_amt)                              AS max_reimbursement,
            SUM(CAST(f.deductible_amt_paid AS DECIMAL(14,2)))           AS total_deductible,

            COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,

            -- Count unique attending physicians via Silver (not in fact table)
            (SELECT COUNT(DISTINCT s.attending_physician_id)
             FROM silver.stg_claims s
             WHERE s.provider_id = dp.provider_id
               AND s.attending_physician_id IS NOT NULL)                AS unique_attending_physicians,

            AVG(CAST(f.claim_duration_days AS DECIMAL(8,2)))            AS avg_claim_duration_days,
            AVG(CAST(f.admission_duration_days AS DECIMAL(8,2)))        AS avg_admission_duration_days,
            AVG(CAST(f.diagnosis_code_count AS DECIMAL(6,2)))           AS avg_diagnosis_code_count,
            AVG(CAST(f.procedure_code_count AS DECIMAL(6,2)))           AS avg_procedure_code_count,

            SUM(CAST(f.is_zero_reimbursement AS INT))                   AS zero_reimbursement_claims,
            SUM(CAST(f.is_same_day_discharge AS INT))                   AS same_day_discharge_claims,

            -- Deceased patient claims (fraud signal)
            SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_patient_claims

        FROM gold.fact_claims f
        INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
        INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
        GROUP BY dp.provider_id, dp.is_potential_fraud, dp.fraud_label;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 7: gold.agg_state_monthly
        -- State + month rollup
        -- Powers Page 6 (Geographic & Trend Analysis)
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.agg_state_monthly';
        TRUNCATE TABLE gold.agg_state_monthly;

        PRINT '>> Inserting Data Into: gold.agg_state_monthly';
        INSERT INTO gold.agg_state_monthly (
            state_code, state_name, state_abbr, region,
            year_num, month_num, month_name, year_month,
            total_claims, total_ip_claims, total_op_claims,
            total_reimbursement, avg_reimbursement_per_claim,
            unique_providers, unique_beneficiaries,
            fraud_provider_claims
        )
        SELECT
            dg.state_code,
            dg.state_name,
            dg.state_abbr,
            dg.region,
            dd.year_num,
            dd.month_num,
            dd.month_name,
            dd.year_month,

            COUNT(f.claim_key)                                              AS total_claims,
            SUM(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 ELSE 0 END)   AS total_ip_claims,
            SUM(CASE WHEN f.claim_type = 'Outpatient' THEN 1 ELSE 0 END)   AS total_op_claims,

            SUM(CAST(f.claim_reimbursement_amt AS BIGINT))                  AS total_reimbursement,
            AVG(CAST(f.claim_reimbursement_amt AS DECIMAL(12,2)))           AS avg_reimbursement_per_claim,

            COUNT(DISTINCT f.provider_key)                                  AS unique_providers,
            COUNT(DISTINCT f.beneficiary_key)                               AS unique_beneficiaries,

            SUM(CASE WHEN f.is_potential_fraud = 1 THEN 1 ELSE 0 END)      AS fraud_provider_claims

        FROM gold.fact_claims f
        INNER JOIN gold.dim_date dd ON dd.date_key = f.claim_start_date_key
        LEFT  JOIN gold.dim_geography dg ON dg.geo_key = f.geo_key
        GROUP BY
            dg.state_code, dg.state_name, dg.state_abbr, dg.region,
            dd.year_num, dd.month_num, dd.month_name, dd.year_month;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- -----------------------------------------------
        -- TABLE 8: gold.agg_chronic_disease
        -- Disease-level rollup
        -- Powers Page 4 (Beneficiary & Chronic Disease)
        -- -----------------------------------------------
        SET @start_time = GETDATE();
        PRINT '>> Truncating Table: gold.agg_chronic_disease';
        TRUNCATE TABLE gold.agg_chronic_disease;

        PRINT '>> Inserting Data Into: gold.agg_chronic_disease';

        -- Unpivot chronic disease flags into rows first,
        -- then aggregate per disease
        WITH disease_unpivot AS (
            SELECT beneficiary_id, 'Alzheimer'            AS disease_name, has_alzheimer           AS has_condition, chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Heart Failure',        has_heart_failure,         chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Kidney Disease',       has_kidney_disease,        chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Cancer',               has_cancer,                chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Obstructive Pulmonary',has_obstr_pulmonary,       chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Depression',           has_depression,            chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Diabetes',             has_diabetes,              chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Ischemic Heart',       has_ischemic_heart,        chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Osteoporosis',         has_osteoporosis,          chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Rheumatoid Arthritis', has_rheumatoid_arthritis,  chronic_condition_count FROM silver.stg_beneficiary
            UNION ALL
            SELECT beneficiary_id, 'Stroke',               has_stroke,                chronic_condition_count FROM silver.stg_beneficiary
        ),
        disease_summary AS (
            SELECT
                disease_name,
                SUM(has_condition)                          AS total_beneficiaries,
                AVG(CAST(chronic_condition_count AS DECIMAL(6,2))) AS avg_chronic_count
            FROM disease_unpivot
            WHERE has_condition = 1
            GROUP BY disease_name
        ),
        disease_claims AS (
            SELECT
                du.disease_name,
                COUNT(f.claim_key)                          AS total_claims,
                SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS total_reimbursement
            FROM disease_unpivot du
            INNER JOIN gold.fact_claims f
                ON f.beneficiary_key = (
                    SELECT beneficiary_key
                    FROM gold.dim_beneficiary db
                    WHERE db.beneficiary_id = du.beneficiary_id
                )
            WHERE du.has_condition = 1
            GROUP BY du.disease_name
        )
        INSERT INTO gold.agg_chronic_disease (
            disease_name, total_beneficiaries, pct_of_all_beneficiaries,
            total_claims, total_reimbursement,
            avg_reimbursement_per_patient,
            avg_chronic_count_for_patients_with_this
        )
        SELECT
            ds.disease_name,
            ds.total_beneficiaries,
            CAST(ds.total_beneficiaries AS DECIMAL(10,2)) /
                (SELECT COUNT(*) FROM silver.stg_beneficiary) * 100   AS pct_of_all_beneficiaries,
            dc.total_claims,
            dc.total_reimbursement,
            CAST(dc.total_reimbursement AS DECIMAL(14,2)) /
                NULLIF(ds.total_beneficiaries, 0)                      AS avg_reimbursement_per_patient,
            ds.avg_chronic_count
        FROM disease_summary ds
        INNER JOIN disease_claims dc ON dc.disease_name = ds.disease_name;

        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @batch_end_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Gold Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
        PRINT '================================================';

    END TRY
    BEGIN CATCH
        PRINT '================================================';
        PRINT 'ERROR OCCURED DURING LOADING GOLD LAYER';
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
EXEC gold.load_gold;
GO

-- =====================================================
-- Verify Gold row counts
-- =====================================================
SELECT 'gold.dim_provider'         AS table_name, COUNT(*) AS row_count FROM gold.dim_provider
UNION ALL
SELECT 'gold.dim_beneficiary',                     COUNT(*)             FROM gold.dim_beneficiary
UNION ALL
SELECT 'gold.dim_date',                            COUNT(*)             FROM gold.dim_date
UNION ALL
SELECT 'gold.dim_geography',                       COUNT(*)             FROM gold.dim_geography
UNION ALL
SELECT 'gold.fact_claims',                         COUNT(*)             FROM gold.fact_claims
UNION ALL
SELECT 'gold.agg_provider_summary',                COUNT(*)             FROM gold.agg_provider_summary
UNION ALL
SELECT 'gold.agg_state_monthly',                   COUNT(*)             FROM gold.agg_state_monthly
UNION ALL
SELECT 'gold.agg_chronic_disease',                 COUNT(*)             FROM gold.agg_chronic_disease;
GO
