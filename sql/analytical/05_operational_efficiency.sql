/* ============================================================
   FILE: 05_operational_efficiency.sql
   PURPOSE: Operational Efficiency & Claims Intelligence analytics.
            Answers operations team questions that drive
            Page 5 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. Are any providers keeping patients unusually long?
   2. Which providers admit and discharge same day? (billing anomaly)
   3. Which providers consistently max out diagnosis code slots?
   4. Which states have unusually high inpatient costs vs outpatient?
   5. What is the distribution of claim durations?
   6. Where are zero-reimbursement claims concentrated?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: Operational Efficiency KPIs
-- Drives the KPI cards on Page 5
-- =====================================================
SELECT
    -- Inpatient metrics
    AVG(CASE WHEN f.claim_type = 'Inpatient'
        THEN CAST(f.admission_duration_days AS FLOAT) END)      AS avg_length_of_stay,

    MAX(CASE WHEN f.claim_type = 'Inpatient'
        THEN f.admission_duration_days END)                     AS max_length_of_stay,

    -- Same day discharge
    SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT))       AS total_same_day_discharges,

    CAST(SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) AS FLOAT) /
        NULLIF(COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END), 0) * 100
                                                                AS same_day_discharge_rate_pct,

    -- Diagnosis code metrics
    AVG(CAST(f.diagnosis_code_count AS FLOAT))                  AS avg_diagnosis_codes_per_claim,
    MAX(f.diagnosis_code_count)                                 AS max_diagnosis_codes,

    -- Procedure code metrics
    AVG(CAST(f.procedure_code_count AS FLOAT))                  AS avg_procedure_codes_per_claim,

    -- Zero reimbursement
    SUM(CAST(f.is_zero_reimbursement AS INT))                   AS zero_reimbursement_claims,
    CAST(SUM(CAST(f.is_zero_reimbursement AS INT)) AS FLOAT) /
        COUNT(f.claim_key) * 100                                AS zero_reimbursement_pct,

    -- Claim duration
    AVG(CAST(f.claim_duration_days AS FLOAT))                   AS avg_claim_duration_days,
    MAX(f.claim_duration_days)                                  AS max_claim_duration_days

FROM gold.fact_claims f;
GO

-- =====================================================
-- QUERY 2: Length of Stay Analysis by Provider
-- Identifies providers with unusually long stays
-- Drives the LOS histogram and bar chart on Page 5
-- =====================================================
WITH global_los AS (
    SELECT
        AVG(CAST(admission_duration_days AS FLOAT))     AS global_avg_los,
        STDEV(CAST(admission_duration_days AS FLOAT))   AS global_stddev_los
    FROM gold.fact_claims
    WHERE claim_type = 'Inpatient'
      AND admission_duration_days IS NOT NULL
)
SELECT
    dp.provider_id,
    dp.fraud_label,
    dp.is_potential_fraud,

    -- LOS metrics
    COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END)      AS ip_claims,
    AVG(CASE WHEN f.claim_type = 'Inpatient'
        THEN CAST(f.admission_duration_days AS FLOAT) END)       AS avg_los,
    MAX(CASE WHEN f.claim_type = 'Inpatient'
        THEN f.admission_duration_days END)                      AS max_los,
    MIN(CASE WHEN f.claim_type = 'Inpatient'
        THEN f.admission_duration_days END)                      AS min_los,

    -- vs benchmark
    gl.global_avg_los,
    gl.global_stddev_los,
    AVG(CASE WHEN f.claim_type = 'Inpatient'
        THEN CAST(f.admission_duration_days AS FLOAT) END) -
        gl.global_avg_los                                        AS vs_avg_los,

    -- Outlier stays (>14 days)
    COUNT(CASE WHEN f.claim_type = 'Inpatient'
        AND f.admission_duration_days > 14 THEN 1 END)          AS extended_stays,

    -- Outlier stays (>30 days)
    COUNT(CASE WHEN f.claim_type = 'Inpatient'
        AND f.admission_duration_days > 30 THEN 1 END)          AS extreme_stays,

    -- LOS anomaly flag
    CASE
        WHEN AVG(CASE WHEN f.claim_type = 'Inpatient'
             THEN CAST(f.admission_duration_days AS FLOAT) END) >
             gl.global_avg_los + (2 * gl.global_stddev_los)
        THEN 'Extreme Outlier (>2 SD)'
        WHEN AVG(CASE WHEN f.claim_type = 'Inpatient'
             THEN CAST(f.admission_duration_days AS FLOAT) END) >
             gl.global_avg_los + gl.global_stddev_los
        THEN 'Outlier (>1 SD)'
        ELSE 'Normal'
    END                                                          AS los_anomaly_flag

FROM gold.fact_claims f
INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
CROSS JOIN global_los gl
GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud,
         gl.global_avg_los, gl.global_stddev_los
HAVING COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END) >= 10
ORDER BY avg_los DESC;
GO

-- =====================================================
-- QUERY 3: Same Day Discharge Analysis
-- Known fraud signal — admits and immediately discharges
-- Drives the same-day bar chart on Page 5
-- =====================================================
WITH global_same_day AS (
    SELECT
        CAST(SUM(CAST(ISNULL(is_same_day_discharge, 0) AS INT)) AS FLOAT) /
            NULLIF(COUNT(CASE WHEN claim_type = 'Inpatient' THEN 1 END), 0) * 100
                                                                AS global_same_day_rate
    FROM gold.fact_claims
)
SELECT
    dp.provider_id,
    dp.fraud_label,
    dp.is_potential_fraud,

    COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END)      AS total_ip_claims,
    SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT))        AS same_day_count,

    CAST(SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) AS FLOAT) /
        NULLIF(COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END), 0) * 100
                                                                AS same_day_rate_pct,

    gl.global_same_day_rate,

    -- vs benchmark
    CAST(SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) AS FLOAT) /
        NULLIF(COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END), 0) * 100 -
        gl.global_same_day_rate                                 AS vs_benchmark_pct,

    -- Reimbursement from same-day admits
    SUM(CASE WHEN ISNULL(f.is_same_day_discharge, 0) = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS same_day_reimbursement,

    -- Same day flag
    CASE
        WHEN CAST(SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) AS FLOAT) /
             NULLIF(COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END), 0) > 0.15
        THEN '🔴 High Risk (>15%)'
        WHEN CAST(SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) AS FLOAT) /
             NULLIF(COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END), 0) > 0.05
        THEN '🟡 Elevated (>5%)'
        ELSE '🟢 Normal'
    END                                                         AS same_day_risk_flag,

    RANK() OVER (ORDER BY
        SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT)) DESC)
                                                                AS same_day_rank

FROM gold.fact_claims f
INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
CROSS JOIN global_same_day gl
GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud,
         gl.global_same_day_rate
HAVING COUNT(CASE WHEN f.claim_type = 'Inpatient' THEN 1 END) >= 5
ORDER BY same_day_count DESC;
GO

-- =====================================================
-- QUERY 4: Diagnosis Code Padding Detection
-- Providers consistently using all 10 diagnosis slots
-- Known fraud signal — padding claims for higher billing
-- Drives the scatter chart on Page 5
-- =====================================================
WITH global_diag AS (
    SELECT
        AVG(CAST(diagnosis_code_count AS FLOAT))    AS global_avg_diag,
        STDEV(CAST(diagnosis_code_count AS FLOAT))  AS global_stddev_diag
    FROM gold.fact_claims
)
SELECT
    dp.provider_id,
    dp.fraud_label,
    dp.is_potential_fraud,

    COUNT(f.claim_key)                                          AS total_claims,
    AVG(CAST(f.diagnosis_code_count AS FLOAT))                  AS avg_diagnosis_codes,
    MAX(f.diagnosis_code_count)                                 AS max_diagnosis_codes,

    -- Claims with all 10 diagnosis codes filled
    COUNT(CASE WHEN f.diagnosis_code_count = 10 THEN 1 END)    AS claims_with_max_codes,
    CAST(COUNT(CASE WHEN f.diagnosis_code_count = 10 THEN 1 END) AS FLOAT) /
        NULLIF(COUNT(f.claim_key), 0) * 100                     AS max_code_claims_pct,

    -- vs global benchmark
    gd.global_avg_diag,
    AVG(CAST(f.diagnosis_code_count AS FLOAT)) - gd.global_avg_diag
                                                                AS vs_avg_diag_codes,

    -- Padding risk flag
    CASE
        WHEN AVG(CAST(f.diagnosis_code_count AS FLOAT)) > 9.5  THEN '🔴 High Padding Risk'
        WHEN AVG(CAST(f.diagnosis_code_count AS FLOAT)) > 9.0  THEN '🟠 Elevated'
        WHEN AVG(CAST(f.diagnosis_code_count AS FLOAT)) > 8.5  THEN '🟡 Moderate'
        ELSE '🟢 Normal'
    END                                                         AS padding_risk_flag,

    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,

    RANK() OVER (ORDER BY AVG(CAST(f.diagnosis_code_count AS FLOAT)) DESC)
                                                                AS padding_rank

FROM gold.fact_claims f
INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
CROSS JOIN global_diag gd
GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud,
         gd.global_avg_diag
HAVING COUNT(f.claim_key) >= 20
ORDER BY avg_diagnosis_codes DESC;
GO

-- =====================================================
-- QUERY 5: IP vs OP Efficiency by State
-- Are some states over-using inpatient vs outpatient?
-- Drives the grouped bar chart on Page 5
-- =====================================================
WITH state_metrics AS (
    SELECT
        dg.state_name,
        dg.state_abbr,
        dg.region,

        COUNT(f.claim_key)                                      AS total_claims,
        COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END) AS ip_claims,
        COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END) AS op_claims,

        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        SUM(CASE WHEN f.claim_type = 'Inpatient'
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS ip_reimbursement,
        SUM(CASE WHEN f.claim_type = 'Outpatient'
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS op_reimbursement,

        AVG(CASE WHEN f.claim_type = 'Inpatient'
            THEN CAST(f.claim_reimbursement_amt AS FLOAT) END)  AS ip_avg_reimbursement,
        AVG(CASE WHEN f.claim_type = 'Outpatient'
            THEN CAST(f.claim_reimbursement_amt AS FLOAT) END)  AS op_avg_reimbursement

    FROM gold.fact_claims f
    INNER JOIN gold.dim_geography dg ON dg.geo_key = f.geo_key
    GROUP BY dg.state_name, dg.state_abbr, dg.region
)
SELECT
    sm.state_name,
    sm.state_abbr,
    sm.region,
    sm.total_claims,
    sm.ip_claims,
    sm.op_claims,
    sm.total_reimbursement,
    sm.ip_reimbursement,
    sm.op_reimbursement,
    sm.ip_avg_reimbursement,
    sm.op_avg_reimbursement,

    -- IP to OP ratio (higher = more inpatient heavy)
    CAST(sm.ip_claims AS FLOAT) /
        NULLIF(sm.op_claims, 0)                                 AS ip_op_ratio,

    -- IP % of total reimbursement
    CAST(sm.ip_reimbursement AS FLOAT) /
        NULLIF(sm.total_reimbursement, 0) * 100                 AS ip_reimbursement_pct,

    -- vs national IP avg
    sm.ip_avg_reimbursement -
        AVG(sm.ip_avg_reimbursement) OVER ()                    AS vs_national_ip_avg,

    -- Efficiency flag
    CASE
        WHEN CAST(sm.ip_claims AS FLOAT) /
             NULLIF(sm.op_claims, 0) >
             AVG(CAST(sm.ip_claims AS FLOAT) /
             NULLIF(sm.op_claims, 0)) OVER () * 1.5
        THEN '🔴 Inpatient Heavy'
        WHEN CAST(sm.ip_claims AS FLOAT) /
             NULLIF(sm.op_claims, 0) >
             AVG(CAST(sm.ip_claims AS FLOAT) /
             NULLIF(sm.op_claims, 0)) OVER () * 1.2
        THEN '🟡 Slightly Elevated'
        ELSE '🟢 Normal'
    END                                                         AS efficiency_flag,

    RANK() OVER (ORDER BY sm.total_reimbursement DESC)          AS state_rank

FROM state_metrics sm
ORDER BY sm.total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 6: Claim Duration Distribution
-- Bucket claims by duration for histogram
-- Drives the duration histogram on Page 5
-- =====================================================
SELECT
    CASE
        WHEN f.claim_duration_days = 0  THEN '0 days (Same Day)'
        WHEN f.claim_duration_days <= 3 THEN '1-3 days'
        WHEN f.claim_duration_days <= 7 THEN '4-7 days'
        WHEN f.claim_duration_days <= 14 THEN '8-14 days'
        WHEN f.claim_duration_days <= 30 THEN '15-30 days'
        ELSE '30+ days'
    END                                                         AS duration_bucket,
    f.claim_type,
    COUNT(f.claim_key)                                          AS claim_count,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement,

    CAST(COUNT(f.claim_key) AS FLOAT) /
        SUM(COUNT(f.claim_key)) OVER () * 100                   AS pct_of_total,

    CASE
        WHEN f.claim_duration_days = 0  THEN 1
        WHEN f.claim_duration_days <= 3 THEN 2
        WHEN f.claim_duration_days <= 7 THEN 3
        WHEN f.claim_duration_days <= 14 THEN 4
        WHEN f.claim_duration_days <= 30 THEN 5
        ELSE 6
    END                                                         AS sort_order

FROM gold.fact_claims f
GROUP BY
    CASE
        WHEN f.claim_duration_days = 0  THEN '0 days (Same Day)'
        WHEN f.claim_duration_days <= 3 THEN '1-3 days'
        WHEN f.claim_duration_days <= 7 THEN '4-7 days'
        WHEN f.claim_duration_days <= 14 THEN '8-14 days'
        WHEN f.claim_duration_days <= 30 THEN '15-30 days'
        ELSE '30+ days'
    END,
    f.claim_type,
    CASE
        WHEN f.claim_duration_days = 0  THEN 1
        WHEN f.claim_duration_days <= 3 THEN 2
        WHEN f.claim_duration_days <= 7 THEN 3
        WHEN f.claim_duration_days <= 14 THEN 4
        WHEN f.claim_duration_days <= 30 THEN 5
        ELSE 6
    END
ORDER BY sort_order, f.claim_type;
GO
