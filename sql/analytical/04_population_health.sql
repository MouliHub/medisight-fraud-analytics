/* ============================================================
   FILE: 04_population_health.sql
   PURPOSE: Population Health & Chronic Disease analytics.
            Answers healthcare operations questions that drive
            Page 4 of the Power BI solution.

   BUSINESS QUESTIONS ANSWERED:
   1. Which patient populations drive the highest costs?
   2. Which chronic diseases generate the most reimbursement?
   3. Who are our high-utilizer patients?
   4. Are deceased beneficiaries still generating claims?
   5. Which age-gender combinations are highest cost?
   6. Where are preventive care opportunities?
   ============================================================ */

USE MediSight;
GO

-- =====================================================
-- QUERY 1: Population Health Summary KPIs
-- Drives the KPI cards on Page 4
-- =====================================================
-- Query 1: Population Health Summary KPIs
-- High utilizer count computed separately to avoid nested aggregate error
SELECT
    COUNT(DISTINCT db.beneficiary_id)                           AS total_beneficiaries,
    AVG(CAST(db.chronic_condition_count AS FLOAT))              AS avg_chronic_conditions,
    AVG(CAST(db.patient_age AS FLOAT))                          AS avg_patient_age,
    SUM(CAST(db.is_deceased AS INT))                            AS deceased_beneficiaries,
    CAST(SUM(CAST(db.is_deceased AS INT)) AS FLOAT) /
        COUNT(DISTINCT db.beneficiary_id) * 100                 AS deceased_pct,
    SUM(CASE WHEN db.is_deceased = 1 THEN 1 ELSE 0 END)        AS claims_from_deceased,
    SUM(CASE WHEN db.gender = 'Male'   THEN 1 ELSE 0 END)      AS male_beneficiaries,
    SUM(CASE WHEN db.gender = 'Female' THEN 1 ELSE 0 END)      AS female_beneficiaries
FROM gold.fact_claims f
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key;

-- High utilizer count (separate query — top 10% by reimbursement)
WITH bene_totals AS (
    SELECT
        beneficiary_key,
        SUM(CAST(claim_reimbursement_amt AS BIGINT)) AS total_reimb
    FROM gold.fact_claims
    GROUP BY beneficiary_key
),
ranked AS (
    SELECT
        beneficiary_key,
        total_reimb,
        NTILE(10) OVER (ORDER BY total_reimb DESC) AS decile
    FROM bene_totals
)
SELECT
    COUNT(*)                                                    AS high_utilizer_count,
    SUM(total_reimb)                                            AS high_utilizer_reimbursement,
    AVG(CAST(total_reimb AS FLOAT))                             AS avg_high_utilizer_reimbursement
FROM ranked
WHERE decile = 1;
GO

-- =====================================================
-- QUERY 2: Age-Gender Population Analysis
-- Drives the population pyramid on Page 4
-- =====================================================
SELECT
    db.age_group,
    db.gender,
    COUNT(DISTINCT db.beneficiary_id)                           AS beneficiary_count,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,
    AVG(CAST(db.chronic_condition_count AS FLOAT))              AS avg_chronic_conditions,

    -- Cost per beneficiary
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) /
        NULLIF(COUNT(DISTINCT db.beneficiary_id), 0)            AS avg_cost_per_beneficiary,

    -- Claims per beneficiary
    CAST(COUNT(f.claim_key) AS FLOAT) /
        NULLIF(COUNT(DISTINCT db.beneficiary_id), 0)            AS avg_claims_per_beneficiary,

    -- % of total reimbursement
    CAST(SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) AS FLOAT) /
        SUM(SUM(CAST(f.claim_reimbursement_amt AS BIGINT))) OVER () * 100
                                                                AS pct_of_total_reimbursement

FROM gold.fact_claims f
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
WHERE db.gender IS NOT NULL
  AND db.age_group IS NOT NULL
GROUP BY db.age_group, db.gender
ORDER BY db.age_group, db.gender;
GO

-- =====================================================
-- QUERY 3: Chronic Disease Burden Analysis
-- Drives the disease burden matrix on Page 4
-- =====================================================
SELECT
    acd.disease_name,
    acd.total_beneficiaries,
    acd.pct_of_all_beneficiaries,
    acd.total_claims,
    acd.total_reimbursement,
    acd.avg_reimbursement_per_patient,
    acd.avg_chronic_count_for_patients_with_this,

    -- Disease cost burden rank
    RANK() OVER (ORDER BY acd.total_reimbursement DESC)         AS cost_rank,
    RANK() OVER (ORDER BY acd.total_beneficiaries DESC)         AS prevalence_rank,
    RANK() OVER (ORDER BY acd.avg_reimbursement_per_patient DESC) AS cost_per_patient_rank,

    -- Cost intensity (reimbursement per beneficiary vs overall avg)
    acd.avg_reimbursement_per_patient /
        NULLIF(
            AVG(acd.avg_reimbursement_per_patient) OVER (),
            0
        ) * 100                                                 AS cost_intensity_pct,

    -- Prevention opportunity score
    -- High prevalence + high cost = highest opportunity
    CAST(acd.total_beneficiaries AS FLOAT) /
        NULLIF(MAX(acd.total_beneficiaries) OVER(), 0) * 50 +
    CAST(acd.avg_reimbursement_per_patient AS FLOAT) /
        NULLIF(MAX(acd.avg_reimbursement_per_patient) OVER(), 0) * 50
                                                                AS prevention_opportunity_score

FROM gold.agg_chronic_disease acd
ORDER BY acd.total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 4: High Utilizer Patient Analysis
-- Top 10% patients by total reimbursement
-- Drives the scatter plot on Page 4
-- =====================================================
WITH beneficiary_totals AS (
    SELECT
        f.beneficiary_key,
        COUNT(f.claim_key)                                      AS total_claims,
        SUM(CAST(f.claim_reimbursement_amt AS BIGINT))          AS total_reimbursement,
        COUNT(DISTINCT f.provider_key)                          AS unique_providers,
        COUNT(CASE WHEN f.claim_type = 'Inpatient'  THEN 1 END) AS ip_claims,
        COUNT(CASE WHEN f.claim_type = 'Outpatient' THEN 1 END) AS op_claims,
        AVG(CAST(f.claim_duration_days AS FLOAT))               AS avg_claim_duration
    FROM gold.fact_claims f
    GROUP BY f.beneficiary_key
),
percentiles AS (
    SELECT
        AVG(CAST(total_reimbursement AS FLOAT)) +
            (2 * STDEV(CAST(total_reimbursement AS FLOAT)))     AS p90,
        AVG(CAST(total_reimbursement AS FLOAT)) +
            STDEV(CAST(total_reimbursement AS FLOAT))           AS p75,
        AVG(CAST(total_reimbursement AS FLOAT))                 AS avg_reimb
    FROM beneficiary_totals
)
SELECT
    db.beneficiary_id,
    db.age_group,
    db.gender,
    db.patient_age,
    db.is_deceased,
    db.chronic_condition_count,
    db.state_code,

    -- Chronic conditions
    db.has_alzheimer,
    db.has_heart_failure,
    db.has_kidney_disease,
    db.has_cancer,
    db.has_diabetes,
    db.has_depression,
    db.has_stroke,

    -- Utilization
    bt.total_claims,
    bt.total_reimbursement,
    bt.unique_providers,
    bt.ip_claims,
    bt.op_claims,
    bt.avg_claim_duration,

    -- Benchmarks
    p.avg_reimb                                                 AS avg_beneficiary_reimbursement,
    p.p90                                                       AS p90_threshold,

    -- Utilizer tier
    CASE
        WHEN bt.total_reimbursement >= p.p90 THEN 'High Utilizer (Top 10%)'
        WHEN bt.total_reimbursement >= p.p75 THEN 'Moderate Utilizer (Top 25%)'
        ELSE 'Standard Utilizer'
    END                                                         AS utilizer_tier,

    -- vs average
    CAST(bt.total_reimbursement - p.avg_reimb AS FLOAT) /
        NULLIF(p.avg_reimb, 0) * 100                            AS vs_avg_pct,

    -- Rank
    RANK() OVER (ORDER BY bt.total_reimbursement DESC)          AS utilizer_rank

FROM beneficiary_totals bt
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = bt.beneficiary_key
CROSS JOIN percentiles p
WHERE bt.total_reimbursement >= p.p75    -- Top 25% for scatter plot
ORDER BY bt.total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 5: Deceased Patient Claims Alert
-- Critical fraud signal — claims for dead patients
-- Drives the alert table on Page 4
-- =====================================================
SELECT
    db.beneficiary_id,
    db.date_of_birth,
    db.date_of_death,
    db.patient_age,
    db.gender,
    db.state_code,

    -- Claim details
    COUNT(f.claim_key)                                          AS claims_after_death,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    MIN(dd.full_date)                                           AS first_claim_date,
    MAX(dd.full_date)                                           AS last_claim_date,
    COUNT(DISTINCT f.provider_key)                              AS unique_providers,

    -- Days between death and first claim
    -- POSITIVE = claim started AFTER death (fraud signal)
    -- NEGATIVE = claim started before death (legitimate, in-progress claim)
    DATEDIFF(DAY, db.date_of_death, MIN(dd.full_date))         AS days_after_death_first_claim,

    -- Claims that started STRICTLY AFTER death date (clear fraud signal)
    COUNT(CASE WHEN dd.full_date > db.date_of_death THEN 1 END) AS claims_started_after_death,

    -- Provider involvement
    COUNT(DISTINCT CASE WHEN dp.is_potential_fraud = 1
        THEN f.provider_key END)                                AS fraud_providers_involved

FROM gold.fact_claims f
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key     = f.beneficiary_key
INNER JOIN gold.dim_provider    dp ON dp.provider_key        = f.provider_key
INNER JOIN gold.dim_date        dd ON dd.date_key            = f.claim_start_date_key
WHERE db.is_deceased = 1
GROUP BY
    db.beneficiary_id, db.date_of_birth, db.date_of_death,
    db.patient_age, db.gender, db.state_code
ORDER BY total_reimbursement DESC;
GO

-- =====================================================
-- QUERY 6: Chronic Disease Co-occurrence
-- Which conditions occur together most often?
-- Supports population health segmentation on Page 4
-- =====================================================
SELECT
    -- Condition combinations
    CASE WHEN db.has_diabetes       = 1 THEN 'Diabetes '       ELSE '' END +
    CASE WHEN db.has_heart_failure   = 1 THEN 'Heart Failure '  ELSE '' END +
    CASE WHEN db.has_ischemic_heart = 1 THEN 'Ischemic Heart ' ELSE '' END +
    CASE WHEN db.has_kidney_disease = 1 THEN 'Kidney Disease '  ELSE '' END +
    CASE WHEN db.has_depression     = 1 THEN 'Depression '      ELSE '' END
                                                                AS condition_combination,
    db.chronic_condition_count,
    COUNT(DISTINCT db.beneficiary_id)                           AS beneficiary_count,
    COUNT(f.claim_key)                                          AS total_claims,
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT))              AS total_reimbursement,
    AVG(CAST(f.claim_reimbursement_amt AS FLOAT))               AS avg_reimbursement_per_claim,

    -- Cost per beneficiary
    SUM(CAST(f.claim_reimbursement_amt AS BIGINT)) /
        NULLIF(COUNT(DISTINCT db.beneficiary_id), 0)            AS cost_per_beneficiary

FROM gold.fact_claims f
INNER JOIN gold.dim_beneficiary db ON db.beneficiary_key = f.beneficiary_key
WHERE db.chronic_condition_count >= 3       -- Focus on complex patients
GROUP BY
    CASE WHEN db.has_diabetes       = 1 THEN 'Diabetes '       ELSE '' END +
    CASE WHEN db.has_heart_failure   = 1 THEN 'Heart Failure '  ELSE '' END +
    CASE WHEN db.has_ischemic_heart = 1 THEN 'Ischemic Heart ' ELSE '' END +
    CASE WHEN db.has_kidney_disease = 1 THEN 'Kidney Disease '  ELSE '' END +
    CASE WHEN db.has_depression     = 1 THEN 'Depression '      ELSE '' END,
    db.chronic_condition_count
HAVING COUNT(DISTINCT db.beneficiary_id) >= 100   -- Statistically meaningful groups
ORDER BY total_reimbursement DESC;
GO