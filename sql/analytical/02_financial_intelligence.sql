/* ============================================================
   FILE: 02_financial_intelligence.sql
   PURPOSE: Financial Intelligence & Risk Exposure analytics.
            Answers CFO-level business questions that drive
            Page 2 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. What is our total fraud financial exposure?
   2. Which providers are statistical outliers?
   3. What is driving our highest costs?
   4. When did costs spike and why?
   5. Which providers cost significantly more than average?
   6. What are the savings if we cap outlier reimbursements?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: Financial Exposure Waterfall
-- Total → Non-Fraud → Fraud Labeled → At Risk
-- Drives the waterfall chart on Page 2
-- =====================================================
WITH provider_stats AS (
    SELECT
        dp.provider_id,
        dp.is_potential_fraud,
        dp.fraud_label,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        COUNT(f.claim_key)                                      AS total_claims,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimbursement,
        SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)    AS deceased_claims,
        SUM(CAST(f.is_same_day_discharge AS INT))               AS same_day_claims
    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
    INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
    GROUP BY dp.provider_id, dp.is_potential_fraud, dp.fraud_label
),
global_stats AS (
    SELECT
        AVG(avg_reimbursement)  AS global_avg,
        STDEV(avg_reimbursement) AS global_stddev
    FROM provider_stats
)
SELECT
    'Total Reimbursement'   AS category,
    SUM(total_reimbursement) AS amount,
    1                       AS sort_order
FROM provider_stats

UNION ALL

SELECT
    'Non-Fraud Providers',
    SUM(CASE WHEN is_potential_fraud = 0 THEN total_reimbursement ELSE 0 END),
    2
FROM provider_stats

UNION ALL

SELECT
    'Fraud Labeled Providers',
    SUM(CASE WHEN is_potential_fraud = 1 THEN total_reimbursement ELSE 0 END),
    3
FROM provider_stats

UNION ALL

-- "At Risk" = not labeled fraud but exceed 2 standard deviations
SELECT
    'High Risk (Unlabeled)',
    SUM(CASE
        WHEN ps.is_potential_fraud = 0
         AND ps.avg_reimbursement > gs.global_avg + (2 * gs.global_stddev)
        THEN ps.total_reimbursement ELSE 0
    END),
    4
FROM provider_stats ps
CROSS JOIN global_stats gs

ORDER BY sort_order;
GO

-- =====================================================
-- QUERY 2: Provider Reimbursement Distribution
-- Identifies statistical outliers (beyond 2 SD)
-- Drives the distribution histogram on Page 2
-- =====================================================
WITH provider_reimbursement AS (
    SELECT
        dp.provider_id,
        dp.fraud_label,
        dp.is_potential_fraud,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        COUNT(f.claim_key)                                      AS total_claims,
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT))           AS avg_reimbursement_per_claim
    FROM gold.fact_claims f
    INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
    GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud
)
SELECT
    pr.provider_id,
    pr.fraud_label,
    pr.is_potential_fraud,
    pr.total_reimbursement,
    pr.total_claims,
    pr.avg_reimbursement_per_claim,

    -- Statistical benchmarks
    s.mean_reimbursement,
    s.stddev_reimbursement,
    s.mean_reimbursement + s.stddev_reimbursement           AS mean_plus_1sd,
    s.mean_reimbursement + (2 * s.stddev_reimbursement)     AS mean_plus_2sd,

    -- How many SDs above/below mean
    CAST(pr.total_reimbursement - s.mean_reimbursement AS FLOAT) /
        NULLIF(s.stddev_reimbursement, 0)                    AS z_score,

    -- Outlier classification
    CASE
        WHEN pr.total_reimbursement > s.mean_reimbursement + (2 * s.stddev_reimbursement)
            THEN 'Extreme Outlier (>2 SD)'
        WHEN pr.total_reimbursement > s.mean_reimbursement + s.stddev_reimbursement
            THEN 'Outlier (>1 SD)'
        WHEN pr.total_reimbursement > s.mean_reimbursement
            THEN 'Above Average'
        ELSE 'Below Average'
    END                                                      AS outlier_category,

    -- Percentile rank
    PERCENT_RANK() OVER (ORDER BY pr.total_reimbursement) * 100
                                                             AS percentile_rank

FROM provider_reimbursement pr
CROSS JOIN (
    SELECT
        AVG(CAST(total_reimbursement AS FLOAT))  AS mean_reimbursement,
        STDEV(CAST(total_reimbursement AS FLOAT)) AS stddev_reimbursement
    FROM provider_reimbursement
) s
ORDER BY pr.total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 3: Cost Driver Analysis
-- What is driving the highest costs?
-- Drives the decomposition tree on Page 2
-- =====================================================

-- By Claim Type
SELECT
    'Claim Type'            AS dimension,
    f.claim_type            AS dimension_value,
    COUNT(f.claim_key)      AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))  AS avg_reimbursement,
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
                            AS reimbursement_pct
FROM gold.fact_claims f
GROUP BY f.claim_type

UNION ALL

-- By Region
SELECT
    'Region',
    dg.region,
    COUNT(f.claim_key),
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)),
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)),
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
FROM gold.fact_claims f
INNER JOIN gold.dim_geography dg ON dg.geo_key = f.geo_key
GROUP BY dg.region

UNION ALL

-- By Fraud Label
SELECT
    'Fraud Label',
    dp.fraud_label,
    COUNT(f.claim_key),
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)),
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)),
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
FROM gold.fact_claims f
INNER JOIN gold.dim_provider dp ON dp.provider_key = f.provider_key
GROUP BY dp.fraud_label

UNION ALL

-- By Age Group
SELECT
    'Age Group',
    db.age_group,
    COUNT(f.claim_key),
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)),
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)),
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
FROM gold.fact_claims f
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
GROUP BY db.age_group

ORDER BY dimension, reimbursement_pct DESC;
GO

-- =====================================================
-- QUERY 4: Provider Benchmark Table
-- Compares every provider against global average
-- Drives the benchmark table on Page 2
-- =====================================================
WITH global_avg AS (
    SELECT
        AVG(CAST(claim_reimbursement_amt AS FLOAT)) AS global_avg_reimbursement,
        COUNT(claim_key)                            AS global_total_claims,
        SUM(CAST(claim_reimbursement_amt AS BIGINT)) AS global_total_reimbursement
    FROM gold.fact_claims
)
SELECT
    dp.provider_id,
    dp.fraud_label,
    dp.is_potential_fraud,

    -- Volume
    COUNT(f.claim_key)                                          AS total_claims,
    COUNT(DISTINCT f.beneficiary_key)                           AS unique_beneficiaries,

    -- Financial
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,

    -- Benchmark comparison
    ga.global_avg_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        ga.global_avg_reimbursement                             AS vs_benchmark_amt,

    CAST(
        AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) -
        ga.global_avg_reimbursement
        AS FLOAT
    ) / NULLIF(ga.global_avg_reimbursement, 0) * 100           AS vs_benchmark_pct,

    -- Risk signals
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS deceased_patient_claims,
    SUM(CAST(f.is_same_day_discharge AS INT))                   AS same_day_discharges,
    AVG(CAST(f.diagnosis_code_count AS FLOAT))                  AS avg_diagnosis_codes,

    -- Ranking
    RANK() OVER (ORDER BY SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) DESC)
                                                                AS reimbursement_rank,
    RANK() OVER (ORDER BY AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) DESC)
                                                                AS avg_reimbursement_rank,

    -- Benchmark category
    CASE
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             ga.global_avg_reimbursement * 2    THEN 'Critical: >200% of Average'
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             ga.global_avg_reimbursement * 1.5  THEN 'High: >150% of Average'
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             ga.global_avg_reimbursement * 1.2  THEN 'Elevated: >120% of Average'
        WHEN AVG(CAST(f.claim_reimbursement_amt AS FLOAT)) >
             ga.global_avg_reimbursement        THEN 'Above Average'
        ELSE 'At or Below Average'
    END                                                         AS benchmark_category

FROM gold.fact_claims f
INNER JOIN gold.dim_provider    dp ON dp.provider_key    = f.provider_key
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
CROSS JOIN global_avg ga
GROUP BY dp.provider_id, dp.fraud_label, dp.is_potential_fraud,
         ga.global_avg_reimbursement, ga.global_total_claims,
         ga.global_total_reimbursement
ORDER BY total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 5: Reimbursement Cap Savings Analysis
-- What-if: if we cap per-claim reimbursement at $X,
-- how much would we save?
-- Drives the what-if parameter on Page 2
-- =====================================================
WITH cap_scenarios AS (
    SELECT 10000  AS cap_amount UNION ALL
    SELECT 20000  UNION ALL
    SELECT 30000  UNION ALL
    SELECT 40000  UNION ALL
    SELECT 50000
)
SELECT
    c.cap_amount,
    -- Actual total reimbursement
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS actual_total,
    -- Capped total reimbursement
    SUM(CAST(
        CASE WHEN f.claim_reimbursement_amt > c.cap_amount
             THEN c.cap_amount
             ELSE f.claim_reimbursement_amt
        END AS BIGINT))                                         AS capped_total,
    -- Savings
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) -
    SUM(CAST(
        CASE WHEN f.claim_reimbursement_amt > c.cap_amount
             THEN c.cap_amount
             ELSE f.claim_reimbursement_amt
        END AS BIGINT))                                         AS potential_savings,
    -- Claims affected
    COUNT(CASE WHEN f.claim_reimbursement_amt > c.cap_amount
          THEN 1 END)                                           AS claims_above_cap,
    -- % claims affected
    CAST(COUNT(CASE WHEN f.claim_reimbursement_amt > c.cap_amount
               THEN 1 END) AS FLOAT) /
        COUNT(f.claim_key) * 100                                AS pct_claims_affected

FROM gold.fact_claims f
CROSS JOIN cap_scenarios c
GROUP BY c.cap_amount
ORDER BY c.cap_amount;
GO