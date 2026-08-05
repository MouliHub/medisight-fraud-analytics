/* ============================================================
   FILE: 06_geographic_trends.sql
   PURPOSE: Geographic & Temporal Intelligence analytics.
            Answers regional director questions that drive
            Page 6 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. Where is spend concentrated geographically?
   2. Which regions perform above/below national benchmark?
   3. How are claims and costs trending over time?
   4. Which states have high volume AND high cost?
   5. Are there seasonal patterns in claims?
   6. Which states have highest fraud concentration?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: State Performance Summary
-- Drives the filled map and regional table on Page 6
-- =====================================================
WITH national_benchmarks AS (
    SELECT
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS national_avg_reimbursement,
        COUNT(f.claim_key) * 1.0 /
            COUNT(DISTINCT dg.state_code)                       AS national_avg_claims_per_state
    FROM gold.fact_claims f
    INNER JOIN gold.dim_geography dg ON dg.geo_key = f.geo_key
)
SELECT
    dg.state_name,
    dg.state_abbr,
    dg.state_code,
    dg.region,

    -- Volume
    COUNT(f.claim_key)                                          AS total_claims,
    COUNT(DISTINCT f.provider_key)                              AS unique_providers,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,
    COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END)    AS ip_claims,
    COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END)    AS op_claims,

    -- Financial
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,
    SUM(CAST(f.deductible_amt_paid AS DECIMAL(14,2)))           AS total_deductible,

    -- Fraud
    COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END)                                AS fraud_providers,
    SUM(CASE WHEN dp.is_potential_fraud = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS fraud_reimbursement,
    CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0) * 100         AS fraud_rate_pct,

    -- Risk signals
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_patient_claims,
    SUM(CAST(ISNULL(f.is_same_day_discharge, 0) AS INT))        AS same_day_discharges,

    -- vs national benchmark
    nb.national_avg_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        nb.national_avg_reimbursement                           AS vs_national_avg_amt,
    CAST(
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        nb.national_avg_reimbursement
    AS FLOAT) / NULLIF(nb.national_avg_reimbursement, 0) * 100 AS vs_national_avg_pct,

    -- State performance flag
    CASE
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             nb.national_avg_reimbursement * 1.3 THEN '🔴 High Cost State'
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             nb.national_avg_reimbursement * 1.1 THEN '🟡 Above Average'
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) <
             nb.national_avg_reimbursement * 0.9 THEN '🟢 Efficient State'
        ELSE '⚪ Average'
    END                                                         AS performance_flag,

    -- Rankings
    RANK() OVER (ORDER BY SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) DESC)
                                                                AS reimbursement_rank,
    RANK() OVER (ORDER BY COUNT(f.claim_key) DESC)              AS claim_volume_rank,
    RANK() OVER (ORDER BY
        CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
            THEN dp.provider_id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0) DESC)         AS fraud_rate_rank

FROM gold.fact_claims f
INNER JOIN gold.dim_provider    dp ON dp.provider_key  = f.provider_key
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
INNER JOIN gold.dim_geography   dg ON dg.geo_key       = f.geo_key
CROSS JOIN national_benchmarks nb
GROUP BY dg.state_name, dg.state_abbr, dg.state_code, dg.region,
         nb.national_avg_reimbursement, nb.national_avg_claims_per_state
ORDER BY total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 2: Regional Benchmark Analysis
-- Compares each region against national average
-- Drives the regional benchmark table on Page 6
-- =====================================================
WITH nat_totals AS (
    SELECT
        SUM(CAST(claim_reimbursement_amt AS BIGINT))            AS nat_total_reimb,
        COUNT(claim_key)                                        AS nat_total_claims,
        AVG(CAST(claim_reimbursement_amt AS FLOAT))             AS nat_avg_reimb
    FROM gold.fact_claims
)
SELECT
    dg.region,
    COUNT(DISTINCT dg.state_code)                               AS state_count,
    COUNT(f.claim_key)                                          AS total_claims,
    COUNT(DISTINCT f.provider_key)                              AS unique_providers,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,

    -- Fraud
    COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END)                                AS fraud_providers,
    CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0) * 100         AS fraud_rate_pct,

    -- vs national
    n.nat_avg_reimb                                             AS national_avg_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        n.nat_avg_reimb                                         AS vs_national_amt,
    CAST(AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        n.nat_avg_reimb AS FLOAT) /
        NULLIF(n.nat_avg_reimb, 0) * 100                        AS vs_national_pct,

    -- Share of national total
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        n.nat_total_reimb * 100                                 AS pct_of_national_reimbursement,
    CAST(COUNT(f.claim_key) AS FLOAT) /
        n.nat_total_claims * 100                                AS pct_of_national_claims

FROM gold.fact_claims f
INNER JOIN gold.dim_provider  dp ON dp.provider_key = f.provider_key
INNER JOIN gold.dim_geography dg ON dg.geo_key      = f.geo_key
CROSS JOIN nat_totals n
WHERE dg.region != 'Unknown'
GROUP BY dg.region, n.nat_total_reimb, n.nat_total_claims, n.nat_avg_reimb
ORDER BY total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 3: Monthly Trend with Anomaly Detection
-- Detects unusual spikes in claims or reimbursement
-- Drives the trend line with annotations on Page 6
-- =====================================================
WITH monthly AS (
    SELECT
        dd.year_num,
        dd.month_num,
        dd.month_name,
        dd.year_month,
        COUNT(f.claim_key)                                      AS total_claims,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END) AS ip_claims,
        COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END) AS op_claims,
        COUNT(DISTINCT f.provider_key)                          AS active_providers,
        SUM(CASE WHEN dp.is_potential_fraud = 1
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS fraud_reimbursement
    FROM gold.fact_claims f
    INNER JOIN gold.dim_date     dd ON dd.date_key     = f.claim_start_date_key
    INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
    GROUP BY dd.year_num, dd.month_num, dd.month_name, dd.year_month
),
with_stats AS (
    SELECT
        *,
        AVG(CAST(total_reimbursement AS FLOAT)) OVER ()         AS overall_avg,
        STDEV(CAST(total_reimbursement AS FLOAT)) OVER ()       AS overall_stddev,

        -- MoM change
        LAG(total_reimbursement) OVER (ORDER BY year_num, month_num)
                                                                AS prev_month_reimb,
        LAG(total_claims) OVER (ORDER BY year_num, month_num)
                                                                AS prev_month_claims,

        -- 3-month rolling average
        AVG(CAST(total_reimbursement AS FLOAT)) OVER (
            ORDER BY year_num, month_num
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )                                                       AS rolling_3m_avg,

        -- Cumulative running total
        SUM(total_reimbursement) OVER (
            ORDER BY year_num, month_num
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                       AS cumulative_reimbursement
    FROM monthly
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
    active_providers,
    fraud_reimbursement,
    overall_avg,
    overall_stddev,
    rolling_3m_avg,
    cumulative_reimbursement,
    prev_month_reimb,
    prev_month_claims,

    -- MoM growth rates
    CAST(total_reimbursement - prev_month_reimb AS FLOAT) /
        NULLIF(prev_month_reimb, 0) * 100                       AS reimbursement_mom_pct,
    CAST(total_claims - prev_month_claims AS FLOAT) /
        NULLIF(prev_month_claims, 0) * 100                      AS claims_mom_pct,

    -- Anomaly detection (>1.5 SD from mean = anomaly)
    CASE
        WHEN total_reimbursement > overall_avg + (1.5 * overall_stddev)
        THEN '🔴 Anomaly: Unusually High'
        WHEN total_reimbursement < overall_avg - (1.5 * overall_stddev)
        THEN '🟡 Anomaly: Unusually Low'
        ELSE '🟢 Normal'
    END                                                         AS anomaly_flag,

    -- Fraud reimbursement %
    CAST(fraud_reimbursement AS FLOAT) /
        NULLIF(total_reimbursement, 0) * 100                    AS fraud_reimb_pct

FROM with_stats
ORDER BY year_num, month_num;
GO

-- =====================================================
-- QUERY 4: State Performance Scatter
-- X = total claims, Y = total reimbursement
-- Bubble size = fraud provider count
-- Drives the scatter plot on Page 6
-- =====================================================
WITH state_summary AS (
    SELECT
        dg.state_name,
        dg.state_abbr,
        dg.region,
        COUNT(f.claim_key)                                      AS total_claims,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimbursement,
        COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
            THEN dp.provider_id END)                            AS fraud_provider_count,
        COUNT(DISTINCT dp.provider_id)                          AS total_providers
    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider  dp ON dp.provider_key = f.provider_key
    INNER JOIN gold.dim_geography dg ON dg.geo_key      = f.geo_key
    GROUP BY dg.state_name, dg.state_abbr, dg.region
)
SELECT
    ss.state_name,
    ss.state_abbr,
    ss.region,
    ss.total_claims,
    ss.total_reimbursement,
    ss.avg_reimbursement,
    ss.fraud_provider_count,
    ss.total_providers,

    -- Median values for quadrant lines
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY ss.total_claims) OVER ()                       AS median_claims,
    PERCENTILE_CONT(0.50) WITHIN GROUP (
        ORDER BY ss.total_reimbursement) OVER ()                AS median_reimbursement,

    -- Quadrant classification
    CASE
        WHEN ss.total_claims >
             PERCENTILE_CONT(0.50) WITHIN GROUP (
                 ORDER BY ss.total_claims) OVER ()
         AND ss.total_reimbursement >
             PERCENTILE_CONT(0.50) WITHIN GROUP (
                 ORDER BY ss.total_reimbursement) OVER ()
        THEN 'High Volume High Cost'
        WHEN ss.total_claims >
             PERCENTILE_CONT(0.50) WITHIN GROUP (
                 ORDER BY ss.total_claims) OVER ()
        THEN 'High Volume Low Cost'
        WHEN ss.total_reimbursement >
             PERCENTILE_CONT(0.50) WITHIN GROUP (
                 ORDER BY ss.total_reimbursement) OVER ()
        THEN 'Low Volume High Cost'
        ELSE 'Low Volume Low Cost'
    END                                                         AS quadrant

FROM state_summary ss
ORDER BY ss.total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 5: Seasonal Pattern Heatmap
-- Month x Year matrix of reimbursement
-- Drives the heatmap matrix on Page 6
-- =====================================================
SELECT
    dd.month_name,
    dd.month_num,
    dd.year_num,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement,

    -- % of year total (shows seasonal share)
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        NULLIF(SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)))
            OVER (PARTITION BY dd.year_num), 0) * 100           AS pct_of_year_total,

    -- vs same month benchmark
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        AVG(AVG(CAST(f.claim_reimbursement_amt AS FLOAT)))
            OVER (PARTITION BY dd.month_num)                    AS vs_month_avg

FROM gold.fact_claims f
INNER JOIN gold.dim_date dd ON dd.date_key = f.claim_start_date_key
GROUP BY dd.month_name, dd.month_num, dd.year_num
ORDER BY dd.year_num, dd.month_num;
GO

-- =====================================================
-- QUERY 6: Geographic Fraud Concentration
-- Which states have highest fraud density?
-- Supports the fraud heatmap on Page 6
-- =====================================================
SELECT
    dg.state_name,
    dg.state_abbr,
    dg.region,

    COUNT(DISTINCT dp.provider_id)                              AS total_providers,
    COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END)                                AS fraud_providers,
    COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 0
        THEN dp.provider_id END)                                AS clean_providers,

    CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN dp.provider_id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0) * 100         AS fraud_rate_pct,

    -- Fraud financial exposure
    SUM(CASE WHEN dp.is_potential_fraud = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END)
                                                                AS fraud_reimbursement,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,

    CAST(SUM(CASE WHEN dp.is_potential_fraud = 1
        THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END) AS FLOAT) /
        NULLIF(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)), 0) * 100
                                                                AS fraud_exposure_pct,

    -- Fraud concentration rank
    RANK() OVER (ORDER BY
        CAST(COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
            THEN dp.provider_id END) AS FLOAT) /
        NULLIF(COUNT(DISTINCT dp.provider_id), 0) DESC)         AS fraud_rate_rank,

    RANK() OVER (ORDER BY
        SUM(CASE WHEN dp.is_potential_fraud = 1
            THEN CAST(f.claim_reimbursement_amt AS BIGINT) ELSE 0 END) DESC)
                                                                AS fraud_exposure_rank

FROM gold.fact_claims f
INNER JOIN gold.dim_provider  dp ON dp.provider_key = f.provider_key
INNER JOIN gold.dim_geography dg ON dg.geo_key      = f.geo_key
GROUP BY dg.state_name, dg.state_abbr, dg.region
ORDER BY fraud_reimbursement DESC;
GO