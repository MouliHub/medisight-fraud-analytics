/* ============================================================
   FILE: 01_executive_summary.sql
   PURPOSE: Executive Command Center analytics queries.
            Answers the portfolio-level business questions
            that drive Page 1 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. What is the overall portfolio health?
   2. What is our total fraud financial exposure?
   3. Which KPIs require immediate attention?
   4. How are claims trending over time?
   5. What is the IP vs OP split?
   6. Which states drive the most spend?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: Portfolio Health Summary
-- The single most important query — drives all
-- executive KPI cards on Page 1
-- =====================================================
SELECT
    -- Volume metrics
    COUNT(DISTINCT dp.provider_id)                              AS total_providers,
    COUNT(DISTINCT db.beneficiary_id)                           AS total_beneficiaries,
    COUNT(f.claim_key)                                          AS total_claims,

    -- Financial metrics
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,
    SUM(CAST(f.deductible_amt_paid AS DECIMAL(14,2)))           AS total_deductible,

    -- Fraud metrics
    SUM(CAST(dp.is_potential_fraud AS INT))                     AS fraud_providers,
    CAST(SUM(CAST(dp.is_potential_fraud AS INT)) AS FLOAT) /
        COUNT(DISTINCT dp.provider_id) * 100                    AS fraud_rate_pct,

    -- Fraud financial exposure
    SUM(CASE WHEN dp.is_potential_fraud = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0
        END)                                                     AS fraud_reimbursement,

    CAST(
        SUM(CASE WHEN dp.is_potential_fraud = 1
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0
            END) AS FLOAT
    ) / NULLIF(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)), 0) * 100
                                                                 AS fraud_reimbursement_pct,

    -- Risk signals
    SUM(CAST(f.is_same_day_discharge AS INT))                   AS same_day_discharge_count,
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_patient_claims,
    SUM(CAST(f.is_zero_reimbursement AS INT))                   AS zero_reimbursement_claims,

    -- Operational metrics
    AVG(CAST(f.claim_duration_days AS FLOAT))                   AS avg_claim_duration_days,
    AVG(CASE WHEN f.claim_type = 'Inpatient'
        THEN CAST(f.admission_duration_days AS FLOAT) END)      AS avg_admission_days

FROM gold.fact_claims f
INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key;
GO

-- =====================================================
-- QUERY 2: Monthly Trend Analysis
-- Drives the trend line on Page 1 and Page 6
-- Uses window functions for MoM growth calculation
-- =====================================================
WITH monthly_stats AS (
    SELECT
        dd.year_num,
        dd.month_num,
        dd.month_name,
        dd.year_month,
        COUNT(f.claim_key)                                      AS total_claims,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END) AS ip_claims,
        COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END) AS op_claims,
        SUM(CASE WHEN dp.is_potential_fraud = 1
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0
            END)                                                 AS fraud_reimbursement,
        COUNT(DISTINCT f.provider_key)                          AS active_providers
    FROM gold.fact_claims f
    INNER JOIN gold.dim_date     dd ON dd.date_key     = f.claim_start_date_key
    INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
    GROUP BY dd.year_num, dd.month_num, dd.month_name, dd.year_month
)
SELECT
    year_num,
    month_num,
    month_name,
    year_month,
    total_claims,
    total_reimbursement,
    ip_claims,
    op_claims,
    fraud_reimbursement,
    active_providers,

    -- Month-over-month growth using LAG window function
    LAG(total_reimbursement) OVER (ORDER BY year_num, month_num) AS prev_month_reimbursement,

    CAST(
        total_reimbursement -
        LAG(total_reimbursement) OVER (ORDER BY year_num, month_num)
        AS FLOAT
    ) / NULLIF(
        LAG(total_reimbursement) OVER (ORDER BY year_num, month_num), 0
    ) * 100                                                      AS reimbursement_mom_pct,

    -- Running total reimbursement
    SUM(total_reimbursement) OVER (
        ORDER BY year_num, month_num
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                            AS cumulative_reimbursement,

    -- 3-month rolling average
    AVG(CAST(total_reimbursement AS FLOAT)) OVER (
        ORDER BY year_num, month_num
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )                                                            AS rolling_3m_avg_reimbursement

FROM monthly_stats
ORDER BY year_num, month_num;
GO

-- =====================================================
-- QUERY 3: IP vs OP Split Analysis
-- Drives the donut chart and stacked bar on Page 1
-- =====================================================
SELECT
    f.claim_type,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement,
    AVG(CAST(f.claim_duration_days AS FLOAT))                   AS avg_claim_duration,
    SUM(CAST(f.deductible_amt_paid AS DECIMAL(14,2)))           AS total_deductible,
    COUNT(DISTINCT f.provider_key)                              AS unique_providers,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,

    -- % of total
    CAST(COUNT(f.claim_key) AS FLOAT) /
        SUM(COUNT(f.claim_key)) OVER () * 100                   AS claims_pct,

    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
                                                                 AS reimbursement_pct
FROM gold.fact_claims f
GROUP BY f.claim_type;
GO

-- =====================================================
-- QUERY 4: Fraud vs Non-Fraud Financial Comparison
-- Drives the waterfall and stacked bars on Pages 1 & 2
-- =====================================================
SELECT
    dp.fraud_label,
    dp.is_potential_fraud,
    COUNT(DISTINCT dp.provider_id)                              AS provider_count,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,
    AVG(CAST(f.claim_duration_days AS FLOAT))                   AS avg_claim_duration,
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_patient_claims,
    SUM(CAST(f.is_same_day_discharge AS INT))                   AS same_day_discharges,
    AVG(CAST(f.diagnosis_code_count AS FLOAT))                  AS avg_diagnosis_codes,

    -- Reimbursement per provider
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0)               AS avg_reimbursement_per_provider,

    -- Claims per provider
    COUNT(f.claim_key) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0)               AS avg_claims_per_provider

FROM gold.fact_claims f
INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
GROUP BY dp.fraud_label, dp.is_potential_fraud
ORDER BY dp.is_potential_fraud DESC;
GO

-- =====================================================
-- QUERY 5: Top 10 States by Reimbursement
-- Drives the state bar chart on Page 1
-- =====================================================
SELECT TOP 10
    dg.state_name,
    dg.state_abbr,
    dg.region,
    COUNT(f.claim_key)                                          AS total_claims,
    COUNT(DISTINCT f.provider_key)                              AS unique_providers,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,
    SUM(CASE WHEN dp.is_potential_fraud = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0
        END)                                                     AS fraud_reimbursement,
    COUNT(CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END)                                 AS fraud_providers,

    -- Rank by reimbursement
    RANK() OVER (ORDER BY SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) DESC)
                                                                 AS reimbursement_rank

FROM gold.fact_claims f
INNER JOIN gold.dim_provider  dp ON dp.provider_key  = f.provider_key
INNER JOIN gold.dim_geography dg ON dg.geo_key       = f.geo_key
GROUP BY dg.state_name, dg.state_abbr, dg.region
ORDER BY total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 6: Executive Alert Logic
-- Determines which KPIs need attention (RAG status)
-- Drives the alert strip on Page 1
-- =====================================================
WITH kpi_values AS (
    SELECT
        COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
            THEN dp.provider_id END)                            AS fraud_provider_count,
        CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
            THEN dp.provider_id END) AS FLOAT) /
            COUNT(DISTINCT dp.provider_id) * 100                AS fraud_rate_pct,
        SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)    AS deceased_claims,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimbursement,
        SUM(CAST(f.is_same_day_discharge AS INT))               AS same_day_count
    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
    INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
)
SELECT
    'Fraud Rate'            AS kpi_name,
    CAST(fraud_rate_pct AS DECIMAL(5,2)) AS kpi_value,
    CASE
        WHEN fraud_rate_pct > 12 THEN 'RED'
        WHEN fraud_rate_pct > 8  THEN 'AMBER'
        ELSE 'GREEN'
    END                                  AS rag_status,
    CASE
        WHEN fraud_rate_pct > 12 THEN 'Fraud rate exceeds 12% critical threshold'
        WHEN fraud_rate_pct > 8  THEN 'Fraud rate exceeds 8% monitoring threshold'
    END                                  AS alert_message
FROM kpi_values WHERE fraud_rate_pct > 8
UNION ALL
SELECT
    'Deceased Patient Claims',
    CAST(deceased_claims AS DECIMAL(10,0)),
    CASE WHEN deceased_claims > 0 THEN 'RED' ELSE 'GREEN' END,
    CAST(deceased_claims AS VARCHAR) + ' claims found for deceased beneficiaries'
FROM kpi_values WHERE deceased_claims > 0
UNION ALL
SELECT
    'Same Day Discharge',
    CAST(same_day_count AS DECIMAL(10,0)),
    CASE
        WHEN same_day_count > 1000 THEN 'RED'
        WHEN same_day_count > 500  THEN 'AMBER'
        ELSE 'GREEN'
    END,
    CAST(same_day_count AS VARCHAR) + ' same-day admissions detected'
FROM kpi_values WHERE same_day_count > 500;
GO