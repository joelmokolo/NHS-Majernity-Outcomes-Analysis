-- ============================================================
-- PROJECT 1: NHS MATERNITY OUTCOMES ANALYSIS
-- File:      02_data_quality.sql
-- Purpose:   MSDS data completeness and quality assessment
-- Author:    Joel Mokolo
-- Notes:     Data quality analysis is the first responsibility
--            of a Badgernet/MSDS analyst. Incomplete fields
--            affect CNST Maternity Incentive Scheme scoring,
--            national benchmarking and trust performance reports.
-- ============================================================


-- ── Q1: Overall field completeness by trust ──────────────
-- Mirrors what an analyst does before any reporting:
-- understand where the gaps are.
-- ─────────────────────────────────────────────────────────
SELECT
    trust_code,
    COUNT(*)                                                        AS total_episodes,

    -- Booking completeness
    SUM(CASE WHEN booking_week IS NOT NULL THEN 1 ELSE 0 END)       AS booking_wk_present,
    ROUND(
        SUM(CASE WHEN booking_week IS NOT NULL THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS booking_wk_pct,

    -- Gestation completeness
    SUM(CASE WHEN gestation_weeks IS NOT NULL THEN 1 ELSE 0 END)    AS gestation_present,
    ROUND(
        SUM(CASE WHEN gestation_weeks IS NOT NULL THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS gestation_pct,

    -- Ethnicity completeness
    SUM(CASE WHEN ethnicity_code IS NOT NULL THEN 1 ELSE 0 END)     AS ethnicity_present,
    ROUND(
        SUM(CASE WHEN ethnicity_code IS NOT NULL THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS ethnicity_pct,

    -- Smoking completeness
    SUM(CASE WHEN smoking_at_delivery != 'Not recorded' THEN 1 ELSE 0 END) AS smoking_recorded,
    ROUND(
        SUM(CASE WHEN smoking_at_delivery != 'Not recorded' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS smoking_pct

FROM msds_episodes
GROUP BY trust_code
ORDER BY booking_wk_pct ASC;   -- worst completeness first


-- ── Q2: Booking within 10 weeks — CNST KPI ───────────────
-- CNST Maternity Incentive Scheme requires trusts to report
-- the % of women booking by 10 weeks. This is a direct
-- safety indicator — late booking means delayed risk screening.
-- ─────────────────────────────────────────────────────────
SELECT
    e.trust_code,
    t.trust_name,
    COUNT(*)                                                        AS total_bookings,

    -- Denominator: records where booking week is known
    SUM(CASE WHEN e.booking_week IS NOT NULL THEN 1 ELSE 0 END)    AS known_booking_week,

    -- Early booking (≤10 weeks)
    SUM(CASE WHEN e.booked_by_10_weeks = 1 THEN 1 ELSE 0 END)      AS booked_early,

    -- Rate against known denominator
    ROUND(
        SUM(CASE WHEN e.booked_by_10_weeks = 1 THEN 1 ELSE 0 END)
        * 100.0
        / NULLIF(SUM(CASE WHEN e.booking_week IS NOT NULL THEN 1 ELSE 0 END), 0)
    , 1)                                                            AS pct_booked_early,

    -- Missing booking week count — data quality flag
    SUM(CASE WHEN e.booking_week IS NULL THEN 1 ELSE 0 END)        AS missing_booking_week,
    ROUND(
        SUM(CASE WHEN e.booking_week IS NULL THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS pct_missing_booking

FROM msds_episodes e
JOIN dim_trust t ON e.trust_code = t.trust_code
GROUP BY e.trust_code, t.trust_name
ORDER BY pct_booked_early ASC;


-- ── Q3: Delivery method breakdown by trust ───────────────
-- Understanding caesarean section rates is a core maternity
-- safety indicator. Trusts with high emergency CS rates may
-- signal issues with induction management or staffing.
-- ─────────────────────────────────────────────────────────
SELECT
    trust_code,
    delivery_method,
    COUNT(*)                                    AS deliveries,
    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (PARTITION BY trust_code)
    , 1)                                        AS pct_of_trust_deliveries
FROM msds_episodes
GROUP BY trust_code, delivery_method
ORDER BY trust_code, deliveries DESC;


-- ── Q4: Preterm birth rate by trust and deprivation ──────
-- Preterm birth (< 37 weeks) is closely associated with
-- deprivation. This query enables analysis of whether
-- high-deprivation areas show disproportionate preterm rates.
-- ─────────────────────────────────────────────────────────
SELECT
    trust_code,
    CASE
        WHEN imd_decile BETWEEN 1 AND 3 THEN 'Deciles 1-3 (Most deprived)'
        WHEN imd_decile BETWEEN 4 AND 7 THEN 'Deciles 4-7 (Mid)'
        WHEN imd_decile BETWEEN 8 AND 10 THEN 'Deciles 8-10 (Least deprived)'
    END                                         AS deprivation_band,
    COUNT(*)                                    AS total_with_gestation,
    SUM(CASE WHEN preterm = 'Y' THEN 1 ELSE 0 END) AS preterm_count,
    ROUND(
        SUM(CASE WHEN preterm = 'Y' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                  AS preterm_pct
FROM msds_episodes
WHERE gestation_weeks IS NOT NULL
GROUP BY
    trust_code,
    CASE
        WHEN imd_decile BETWEEN 1 AND 3 THEN 'Deciles 1-3 (Most deprived)'
        WHEN imd_decile BETWEEN 4 AND 7 THEN 'Deciles 4-7 (Mid)'
        WHEN imd_decile BETWEEN 8 AND 10 THEN 'Deciles 8-10 (Least deprived)'
    END
ORDER BY trust_code, deprivation_band;


-- ── Q5: Smoking at delivery — SATOD / MSDS KPI ───────────
-- Smoking at delivery is a CQUIN / SATOD nationally reported
-- measure. From 2025-26 MSDS replaces the SATOD collection
-- as the primary source. Recording completeness matters.
-- ─────────────────────────────────────────────────────────
SELECT
    trust_code,
    COUNT(*)                                                            AS total,
    SUM(CASE WHEN smoking_at_delivery = 'Smoker'      THEN 1 ELSE 0 END) AS smokers,
    SUM(CASE WHEN smoking_at_delivery = 'Non-smoker'  THEN 1 ELSE 0 END) AS non_smokers,
    SUM(CASE WHEN smoking_at_delivery = 'Ex-smoker'   THEN 1 ELSE 0 END) AS ex_smokers,
    SUM(CASE WHEN smoking_at_delivery = 'Not recorded' THEN 1 ELSE 0 END) AS not_recorded,
    ROUND(
        SUM(CASE WHEN smoking_at_delivery = 'Smoker' THEN 1 ELSE 0 END)
        * 100.0
        / NULLIF(SUM(CASE WHEN smoking_at_delivery != 'Not recorded' THEN 1 ELSE 0 END), 0)
    , 1)                                                                AS smoker_pct_of_known
FROM msds_episodes
GROUP BY trust_code
ORDER BY smoker_pct_of_known DESC;


-- ── Q6: Monthly trend — deliveries and booking rate ──────
-- Time series view: are booking rates improving month on month?
-- This type of trend analysis is what clinical boards want
-- to see in performance reports.
-- ─────────────────────────────────────────────────────────
SELECT
    report_period_month,
    COUNT(*)                                                        AS total_episodes,
    SUM(CASE WHEN booked_by_10_weeks = 1 THEN 1 ELSE 0 END)        AS booked_early,
    ROUND(
        SUM(CASE WHEN booked_by_10_weeks = 1 THEN 1 ELSE 0 END)
        * 100.0
        / NULLIF(SUM(CASE WHEN booking_week IS NOT NULL THEN 1 ELSE 0 END), 0)
    , 1)                                                            AS early_booking_pct,
    SUM(CASE WHEN delivery_method = 'Emergency CS' THEN 1 ELSE 0 END) AS emergency_cs,
    ROUND(
        SUM(CASE WHEN delivery_method = 'Emergency CS' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                                      AS emergency_cs_pct
FROM msds_episodes
GROUP BY report_period_month
ORDER BY report_period_month;


-- ── Q7: Low birthweight by maternal age band ─────────────
-- Association between maternal age extremes and adverse
-- neonatal outcomes. Useful for targeting antenatal support.
-- ─────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN maternal_age < 20             THEN 'Under 20'
        WHEN maternal_age BETWEEN 20 AND 24 THEN '20-24'
        WHEN maternal_age BETWEEN 25 AND 29 THEN '25-29'
        WHEN maternal_age BETWEEN 30 AND 34 THEN '30-34'
        WHEN maternal_age BETWEEN 35 AND 39 THEN '35-39'
        ELSE '40 and over'
    END                                         AS age_band,
    COUNT(*)                                    AS total,
    SUM(CASE WHEN low_birthweight = 'Y' THEN 1 ELSE 0 END)  AS low_bw_count,
    ROUND(
        SUM(CASE WHEN low_birthweight = 'Y' THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                  AS low_bw_pct,
    ROUND(AVG(CAST(birthweight_grams AS FLOAT)), 0) AS avg_birthweight_g
FROM msds_episodes
GROUP BY
    CASE
        WHEN maternal_age < 20             THEN 'Under 20'
        WHEN maternal_age BETWEEN 20 AND 24 THEN '20-24'
        WHEN maternal_age BETWEEN 25 AND 29 THEN '25-29'
        WHEN maternal_age BETWEEN 30 AND 34 THEN '30-34'
        WHEN maternal_age BETWEEN 35 AND 39 THEN '35-39'
        ELSE '40 and over'
    END
ORDER BY age_band;


-- ── Q8: Breastfeeding initiation by ethnicity ────────────
-- MSDS captures first feed type. Breastfeeding rates vary
-- significantly by ethnicity — this informs targeted support.
-- ─────────────────────────────────────────────────────────
SELECT
    COALESCE(ethnicity_desc, 'Not recorded / Missing') AS ethnicity,
    COUNT(*)                                            AS total,
    SUM(CASE WHEN first_feed_type IN ('Breast milk','Mixed') THEN 1 ELSE 0 END) AS any_breastfeeding,
    ROUND(
        SUM(CASE WHEN first_feed_type IN ('Breast milk','Mixed') THEN 1 ELSE 0 END)
        * 100.0 / COUNT(*), 1)                          AS breastfeeding_pct
FROM msds_episodes
GROUP BY COALESCE(ethnicity_desc, 'Not recorded / Missing')
HAVING COUNT(*) >= 10   -- suppress small numbers (IG best practice)
ORDER BY breastfeeding_pct DESC;
