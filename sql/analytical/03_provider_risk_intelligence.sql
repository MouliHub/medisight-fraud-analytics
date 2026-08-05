/* ============================================================
   FILE: 03_provider_risk_intelligence.sql
   PURPOSE: Provider Risk Intelligence analytics.
            Answers fraud investigation team questions that
            drive Page 3 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. Which providers should we investigate first?
   2. What composite risk score does each provider have?
   3. Which providers are outliers on multiple dimensions?
   4. How do two providers compare side by side?
   5. Which physicians appear across multiple high-risk providers?
   6. What specific risk signals drive each provider's score?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: Provider Composite Risk Score & Watchlist
-- The most important query for fraud investigators
-- Drives the investigation queue on Page 3
-- =====================================================
WITH global_benchmarks AS (
    SELECT
        AVG(CAST(claim_reimbursement_amt AS FLOAT))     AS global_avg_reimbursement,
        STDEV(CAST(claim_reimbursement_amt AS FLOAT))   AS global_stddev_reimbursement,
        AVG(CAST(claim_duration_days AS FLOAT))         AS global_avg_duration,
        AVG(CAST(diagnosis_code_count AS FLOAT))        AS global_avg_diag_codes,
        AVG(CAST(ISNULL(is_same_day_discharge, 0) AS FLOAT)) AS global_same_day_rate
    FROM gold.fact_claims
),
provider_metrics AS (
    SELECT
        dp.provider_id,
        dp.fraud_label,
        dp.is_potential_fraud,

        -- Volume metrics
        COUNT(f.claim_key)                                      AS total_claims,
        COUNT(DISTINCT f.beneficiary_key)                       AS unique_beneficiaries,
        COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END) AS ip_claims,
        COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END) AS op_claims,

        -- Financial metrics
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimbursement,
        MAX(f.claim_reimbursement_amt)                          AS max_single_claim,

        -- Risk signals
        SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)    AS deceased_patient_claims,
        SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT))   AS same_day_discharges,
        AVG(CAST(f.diagnosis_code_count AS FLOAT))              AS avg_diagnosis_codes,
        AVG(CAST(f.procedure_code_count AS FLOAT))              AS avg_procedure_codes,
        SUM(CAST(f.is_zero_reimbursement AS INT))               AS zero_reimbursement_claims,
        AVG(CAST(ISNULL(f.admission_duration_days, 0) AS FLOAT)) AS avg_admission_days

    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
    INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
    GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud
),
risk_scored AS (
    SELECT
        pm.*,
        gb.global_avg_reimbursement,
        gb.global_avg_diag_codes,

        -- vs benchmark %
        CAST(pm.avg_reimbursement - gb.global_avg_reimbursement AS FLOAT) /
            NULLIF(gb.global_avg_reimbursement, 0) * 100       AS vs_benchmark_pct,

        -- Same day discharge rate
        CAST(pm.same_day_discharges AS FLOAT) /
            NULLIF(pm.ip_claims, 0) * 100                      AS same_day_discharge_pct,

        -- ── COMPOSITE RISK SCORE ──────────────────────────
        -- Factor 1: Reimbursement anomaly (0-3 points)
        CASE
            WHEN pm.avg_reimbursement > gb.global_avg_reimbursement * 3   THEN 3
            WHEN pm.avg_reimbursement > gb.global_avg_reimbursement * 2   THEN 2
            WHEN pm.avg_reimbursement > gb.global_avg_reimbursement * 1.5 THEN 1
            ELSE 0
        END +
        -- Factor 2: Deceased patient claims (0-3 points)
        CASE
            WHEN pm.deceased_patient_claims > 10 THEN 3
            WHEN pm.deceased_patient_claims > 5 THEN 2
            WHEN pm.deceased_patient_claims > 0  THEN 1
            ELSE 0
        END +
        -- Factor 3: Same day discharge rate (0-2 points)
        CASE
            WHEN CAST(pm.same_day_discharges AS FLOAT) /
                 NULLIF(pm.ip_claims, 0) > 0.10 THEN 2
            WHEN CAST(pm.same_day_discharges AS FLOAT) /
                 NULLIF(pm.ip_claims, 0) > 0.05 THEN 1
            ELSE 0
        END +
        -- Factor 4: Diagnosis code padding (0-2 points)
        CASE
            WHEN pm.avg_diagnosis_codes > 9.5 THEN 2
            WHEN pm.avg_diagnosis_codes > 8.5 THEN 1
            ELSE 0
        END +
        -- Factor 5: Fraud label (0 or 5 points)
        CASE WHEN pm.is_potential_fraud = 1 THEN 5 ELSE 0 END
                                                                AS risk_score

    FROM provider_metrics pm
    CROSS JOIN global_benchmarks gb
)
SELECT
    rs.provider_id,
    rs.fraud_label,
    rs.is_potential_fraud,
    rs.risk_score,

    -- Risk category
    CASE
        WHEN rs.risk_score >= 9  THEN '🔴 Critical'
        WHEN rs.risk_score >= 6  THEN '🟠 High'
        WHEN rs.risk_score >= 3  THEN '🟡 Medium'
        WHEN rs.risk_score >= 1  THEN '🟢 Low'
        ELSE '⚪ Clean'
    END                                                         AS risk_category,

    -- Metrics
    rs.total_claims,
    rs.unique_beneficiaries,
    rs.ip_claims,
    rs.op_claims,
    rs.total_reimbursement,
    rs.avg_reimbursement,
    rs.global_avg_reimbursement,
    CAST(rs.vs_benchmark_pct AS DECIMAL(8,2))                  AS vs_benchmark_pct,
    rs.deceased_patient_claims,
    rs.same_day_discharges,
    CAST(rs.same_day_discharge_pct AS DECIMAL(8,2))            AS same_day_discharge_pct,
    CAST(rs.avg_diagnosis_codes AS DECIMAL(6,2))               AS avg_diagnosis_codes,
    rs.max_single_claim,
    rs.zero_reimbursement_claims,

    -- Investigation priority rank
    RANK() OVER (ORDER BY rs.risk_score DESC, rs.total_reimbursement DESC)
                                                                AS investigation_priority

FROM risk_scored rs
ORDER BY investigation_priority;
GO

-- =====================================================
-- QUERY 2: Risk Tier Summary
-- Drives the risk tier KPI cards on Page 3
-- =====================================================
WITH risk_scored AS (
    SELECT
        dp.provider_id,
        dp.is_potential_fraud,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimb,

        CASE
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) > (
                SELECT AVG(CAST(claim_reimbursement_amt AS FLOAT)) * 3
                FROM gold.fact_claims) THEN 3
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) > (
                SELECT AVG(CAST(claim_reimbursement_amt AS FLOAT)) * 2
                FROM gold.fact_claims) THEN 2
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) > (
                SELECT AVG(CAST(claim_reimbursement_amt AS FLOAT)) * 1.5
                FROM gold.fact_claims) THEN 1
            ELSE 0
        END +
        CASE WHEN dp.is_potential_fraud = 1 THEN 5 ELSE 0 END  AS risk_score

    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
    GROUP BY dp.provider_id, dp.is_potential_fraud
)
SELECT
    CASE
        WHEN risk_score >= 9 THEN '🔴 Critical'
        WHEN risk_score >= 6 THEN '🟠 High'
        WHEN risk_score >= 3 THEN '🟡 Medium'
        WHEN risk_score >= 1 THEN '🟢 Low'
        ELSE '⚪ Clean'
    END                                                         AS risk_category,
    COUNT(*)                                                    AS provider_count,
    SUM(total_reimbursement)                                    AS total_reimbursement,
    CAST(COUNT(*) AS FLOAT) /
        SUM(COUNT(*)) OVER () * 100                             AS pct_of_providers,
    CASE
        WHEN risk_score >= 9 THEN 1
        WHEN risk_score >= 6 THEN 2
        WHEN risk_score >= 3 THEN 3
        WHEN risk_score >= 1 THEN 4
        ELSE 5
    END                                                         AS sort_order
FROM risk_scored
GROUP BY
    CASE
        WHEN risk_score >= 9 THEN '🔴 Critical'
        WHEN risk_score >= 6 THEN '🟠 High'
        WHEN risk_score >= 3 THEN '🟡 Medium'
        WHEN risk_score >= 1 THEN '🟢 Low'
        ELSE '⚪ Clean'
    END,
    CASE
        WHEN risk_score >= 9 THEN 1
        WHEN risk_score >= 6 THEN 2
        WHEN risk_score >= 3 THEN 3
        WHEN risk_score >= 1 THEN 4
        ELSE 5
    END
ORDER BY sort_order;
GO

-- =====================================================
-- QUERY 3: Risk Signal Breakdown per Provider
-- Shows which specific signals drive each risk score
-- Drives the stacked bar chart on Page 3
-- =====================================================
WITH global_avg AS (
    SELECT AVG(CAST(claim_reimbursement_amt AS FLOAT)) AS avg_reimb
    FROM gold.fact_claims
),
provider_signals AS (
    SELECT
        dp.provider_id,
        dp.fraud_label,
        -- Individual risk signal scores
        CASE
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
                 (SELECT avg_reimb FROM global_avg) * 3   THEN 3
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
                 (SELECT avg_reimb FROM global_avg) * 2   THEN 2
            WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
                 (SELECT avg_reimb FROM global_avg) * 1.5 THEN 1
            ELSE 0
        END                                                     AS reimbursement_signal,

        CASE
            WHEN SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END) > 20 THEN 3
            WHEN SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END) > 10 THEN 2
            WHEN SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END) > 0  THEN 1
            ELSE 0
        END                                                     AS deceased_signal,

        CASE
            WHEN CAST(SUM(CAST(ISNULL(f.is_same_day_discharge,0) AS INT)) AS FLOAT) /
                 NULLIF(COUNT(CASE WHEN f.claim_type='Inpatient' THEN 1 END),0) > 0.15 THEN 2
            WHEN CAST(SUM(CAST(ISNULL(f.is_same_day_discharge,0) AS INT)) AS FLOAT) /
                 NULLIF(COUNT(CASE WHEN f.claim_type='Inpatient' THEN 1 END),0) > 0.05 THEN 1
            ELSE 0
        END                                                     AS same_day_signal,

        CASE
            WHEN AVG(CAST(f.diagnosis_code_count AS FLOAT)) > 9.5 THEN 2
            WHEN AVG(CAST(f.diagnosis_code_count AS FLOAT)) > 8.5 THEN 1
            ELSE 0
        END                                                     AS padding_signal,

        CASE WHEN dp.is_potential_fraud = 1 THEN 5 ELSE 0 END  AS fraud_label_signal,

        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement

    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
    INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
    GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud
)
SELECT TOP 30
    provider_id,
    fraud_label,
    reimbursement_signal,
    deceased_signal,
    same_day_signal,
    padding_signal,
    fraud_label_signal,
    reimbursement_signal + deceased_signal + same_day_signal +
        padding_signal + fraud_label_signal                     AS total_risk_score,
    total_reimbursement
FROM provider_signals
ORDER BY total_risk_score DESC, total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 4: Provider Monthly Claim Timeline
-- Used in the Provider Profile drillthrough page
-- Shows month-by-month behavior for any single provider
-- =====================================================
SELECT
    dp.provider_id,
    dp.fraud_label,
    dd.year_num,
    dd.month_num,
    dd.month_name,
    dd.year_month,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_claims,
    SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT))       AS same_day_discharges,
    AVG(CAST(f.diagnosis_code_count AS FLOAT))                  AS avg_diagnosis_codes,

    -- MoM change per provider
    LAG(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)))
        OVER (PARTITION BY dp.provider_id
              ORDER BY dd.year_num, dd.month_num)               AS prev_month_reimbursement,

    CAST(
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) -
        LAG(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)))
            OVER (PARTITION BY dp.provider_id
                  ORDER BY dd.year_num, dd.month_num)
    AS FLOAT) / NULLIF(
        LAG(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)))
            OVER (PARTITION BY dp.provider_id
                  ORDER BY dd.year_num, dd.month_num)
    , 0) * 100                                                  AS reimbursement_mom_pct

FROM gold.fact_claims f
INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
INNER JOIN gold.dim_date        dd ON dd.date_key        = f.claim_start_date_key
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
GROUP BY dp.provider_id, dp.fraud_label,
         dd.year_num, dd.month_num, dd.month_name, dd.year_month
ORDER BY dp.provider_id, dd.year_num, dd.month_num;
GO

-- =====================================================
-- QUERY 5: Top 20 Providers Full Profile
-- Complete provider detail for investigation queue
-- =====================================================
WITH global_avg AS (
    SELECT AVG(CAST(claim_reimbursement_amt AS FLOAT)) AS avg_reimb
    FROM gold.fact_claims
)
SELECT TOP 20
    dp.provider_id,
    dp.fraud_label,
    dp.is_potential_fraud,
    aps.total_claims,
    aps.total_ip_claims,
    aps.total_op_claims,
    aps.total_reimbursement,
    aps.avg_reimbursement_per_claim,
    aps.max_reimbursement,
    aps.unique_beneficiaries,
    aps.unique_attending_physicians,
    aps.avg_claim_duration_days,
    aps.avg_admission_duration_days,
    aps.avg_diagnosis_code_count,
    aps.avg_procedure_code_count,
    aps.zero_reimbursement_claims,
    aps.same_day_discharge_claims,
    aps.deceased_patient_claims,

    -- vs global benchmark
    ga.avg_reimb                                                AS global_avg_reimbursement,
    CAST(aps.avg_reimbursement_per_claim - ga.avg_reimb AS FLOAT) /
        NULLIF(ga.avg_reimb, 0) * 100                           AS vs_benchmark_pct,

    -- Provider rank
    RANK() OVER (ORDER BY aps.total_reimbursement DESC)         AS reimbursement_rank,
    RANK() OVER (ORDER BY aps.deceased_patient_claims DESC)     AS deceased_rank,
    RANK() OVER (ORDER BY aps.same_day_discharge_claims DESC)   AS same_day_rank

FROM gold.agg_provider_summary aps
INNER JOIN gold.dim_provider dp ON dp.provider_id = aps.provider_id
CROSS JOIN global_avg ga
ORDER BY aps.total_reimbursement DESC;
GO

---

