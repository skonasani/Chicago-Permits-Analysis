-- sql/02_transform.sql
-- ---------------------------------------------------------------
-- Core enrichment queries: raw permit staging → analytics layer
--
-- Dataset: City of Chicago Building Permits
-- Source:  data.cityofchicago.org
-- Grain:   one row per permit application
-- ---------------------------------------------------------------


-- ---------------------------------------------------------------
-- QUERY 1: Annual permit volume with YoY change
-- Skills: LAG window function, EXTRACT, NULLIF guard
-- Business use: Powers the annual trend KPI cards and chart
-- ---------------------------------------------------------------

WITH annual_volume AS (
    SELECT
        EXTRACT(YEAR FROM issue_date)       AS permit_year,
        COUNT(*)                            AS total_permits,
        SUM(estimated_cost)                 AS total_estimated_value,
        COUNT(CASE WHEN work_type = 'NEW CONSTRUCTION' THEN 1 END) AS new_construction_count,
        COUNT(CASE WHEN work_type = 'RENOVATION/ALTERATION' THEN 1 END) AS renovation_count
    FROM stg.chicago_permits
    WHERE issue_date IS NOT NULL
      AND EXTRACT(YEAR FROM issue_date) BETWEEN 2019 AND 2024
    GROUP BY 1
)
SELECT
    permit_year,
    total_permits,
    total_estimated_value,
    new_construction_count,
    renovation_count,
    ROUND(
        new_construction_count::FLOAT / NULLIF(total_permits, 0) * 100, 2
    ) AS new_construction_pct,
    LAG(total_permits) OVER (ORDER BY permit_year)           AS prior_yr_permits,
    ROUND(
        (total_permits - LAG(total_permits) OVER (ORDER BY permit_year))::FLOAT
        / NULLIF(LAG(total_permits) OVER (ORDER BY permit_year), 0) * 100, 2
    ) AS permit_yoy_pct,
    ROUND(
        (total_estimated_value - LAG(total_estimated_value) OVER (ORDER BY permit_year))::FLOAT
        / NULLIF(LAG(total_estimated_value) OVER (ORDER BY permit_year), 0) * 100, 2
    ) AS value_yoy_pct
FROM annual_volume
ORDER BY permit_year;


-- ---------------------------------------------------------------
-- QUERY 2: Community area permit volume with rolling average
-- Skills: PARTITION BY, ROWS BETWEEN, ranking, rolling avg
-- Business use: Neighborhood trend chart and top 10 table
-- ---------------------------------------------------------------

WITH monthly_area AS (
    SELECT
        community_area,
        DATE_TRUNC('month', issue_date)     AS permit_month,
        COUNT(*)                            AS monthly_permits,
        SUM(estimated_cost)                 AS monthly_value
    FROM stg.chicago_permits
    WHERE issue_date IS NOT NULL
      AND community_area IS NOT NULL
    GROUP BY 1, 2
),
enriched AS (
    SELECT
        community_area,
        permit_month,
        monthly_permits,
        monthly_value,
        AVG(monthly_permits) OVER (
            PARTITION BY community_area
            ORDER BY permit_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS rolling_3mo_permits,
        SUM(monthly_permits) OVER (
            PARTITION BY community_area
            ORDER BY permit_month
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) AS trailing_12mo_permits,
        LAG(monthly_permits, 12) OVER (
            PARTITION BY community_area
            ORDER BY permit_month
        ) AS same_month_prior_yr
    FROM monthly_area
)
SELECT
    *,
    ROUND(
        (monthly_permits - same_month_prior_yr)::FLOAT
        / NULLIF(same_month_prior_yr, 0) * 100, 2
    ) AS yoy_pct_change,
    RANK() OVER (
        PARTITION BY DATE_TRUNC('year', permit_month)
        ORDER BY SUM(monthly_permits) OVER (
            PARTITION BY community_area,
            DATE_TRUNC('year', permit_month)
        ) DESC
    ) AS annual_volume_rank
FROM enriched
ORDER BY community_area, permit_month;


-- ---------------------------------------------------------------
-- QUERY 3: New construction share trending over time
-- Skills: Conditional aggregation, FILTER clause, pivot logic
-- Business use: Materials demand signal (new builds = 3-4x
--               more raw materials than renovation)
-- ---------------------------------------------------------------

SELECT
    EXTRACT(YEAR FROM issue_date)           AS permit_year,
    EXTRACT(QUARTER FROM issue_date)        AS permit_quarter,
    COUNT(*)                                AS total_permits,
    COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')
                                            AS new_construction,
    COUNT(*) FILTER (WHERE work_type = 'RENOVATION/ALTERATION')
                                            AS renovation,
    COUNT(*) FILTER (WHERE work_type = 'WRECKING/DEMOLITION')
                                            AS wrecking,
    ROUND(
        COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')::FLOAT
        / NULLIF(COUNT(*), 0) * 100, 2
    ) AS new_construction_share_pct,
    ROUND(
        LAG(
            COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')::FLOAT
            / NULLIF(COUNT(*), 0) * 100, 2
        ) OVER (ORDER BY EXTRACT(YEAR FROM issue_date), EXTRACT(QUARTER FROM issue_date))
        , 2
    ) AS prior_qtr_new_construction_share,
    SUM(estimated_cost) FILTER (WHERE work_type = 'NEW CONSTRUCTION')
                                            AS new_construction_value
FROM stg.chicago_permits
WHERE issue_date IS NOT NULL
  AND EXTRACT(YEAR FROM issue_date) BETWEEN 2019 AND 2024
GROUP BY 1, 2
ORDER BY 1, 2;


-- ---------------------------------------------------------------
-- QUERY 4: Permit value outlier detection and data quality
-- Skills: Percentile functions, statistical flagging, audit pattern
-- Business use: Validates estimated_cost field before dashboards
--               surface it to stakeholders
-- ---------------------------------------------------------------

WITH value_stats AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY estimated_cost) AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY estimated_cost) AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY estimated_cost) AS p75,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY estimated_cost) AS p99,
        AVG(estimated_cost)    AS mean_value,
        STDDEV(estimated_cost) AS stddev_value
    FROM stg.chicago_permits
    WHERE estimated_cost > 0
),
flagged AS (
    SELECT
        p.permit_id,
        p.community_area,
        p.work_type,
        p.estimated_cost,
        s.p50                  AS median_value,
        s.p99                  AS p99_value,
        CASE
            WHEN p.estimated_cost > s.p99
                THEN 'outlier_high'
            WHEN p.estimated_cost <= 0
                THEN 'invalid_zero_or_negative'
            WHEN p.estimated_cost IS NULL
                THEN 'missing'
            ELSE 'normal'
        END                    AS value_flag,
        ROUND(
            (p.estimated_cost - s.mean_value) / NULLIF(s.stddev_value, 0), 2
        )                      AS z_score
    FROM stg.chicago_permits p
    CROSS JOIN value_stats s
)
SELECT
    value_flag,
    COUNT(*)                   AS record_count,
    ROUND(COUNT(*)::FLOAT / SUM(COUNT(*)) OVER () * 100, 2) AS pct_of_total,
    ROUND(AVG(estimated_cost), 2)  AS avg_value,
    MIN(estimated_cost)            AS min_value,
    MAX(estimated_cost)            AS max_value
FROM flagged
GROUP BY value_flag
ORDER BY record_count DESC;


-- ---------------------------------------------------------------
-- QUERY 5: Materials demand forward signal scoring
-- Skills: CASE logic, composite scoring, business translation
-- Business use: Scores community areas by near-term materials
--               demand potential — actionable for procurement teams
-- ---------------------------------------------------------------

WITH area_metrics AS (
    SELECT
        community_area,
        COUNT(*)                            AS total_permits_2024,
        SUM(estimated_cost)                 AS total_value_2024,
        COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')
                                            AS new_construction_2024,
        ROUND(
            COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')::FLOAT
            / NULLIF(COUNT(*), 0) * 100, 2
        )                                   AS new_construction_pct,
        LAG(COUNT(*)) OVER (
            PARTITION BY community_area
            ORDER BY EXTRACT(YEAR FROM issue_date)
        )                                   AS permits_2023
    FROM stg.chicago_permits
    WHERE EXTRACT(YEAR FROM issue_date) = 2024
      AND community_area IS NOT NULL
    GROUP BY community_area, EXTRACT(YEAR FROM issue_date)
),
scored AS (
    SELECT
        community_area,
        total_permits_2024,
        total_value_2024,
        new_construction_pct,
        ROUND(
            (total_permits_2024 - permits_2023)::FLOAT
            / NULLIF(permits_2023, 0) * 100, 2
        )                                   AS volume_yoy_pct,
        CASE
            WHEN new_construction_pct >= 35 AND total_permits_2024 >= 1500
                THEN 3
            WHEN new_construction_pct >= 25 AND total_permits_2024 >= 1000
                THEN 2
            ELSE 1
        END                                 AS new_construction_score,
        CASE
            WHEN total_value_2024 >= 1000000000  THEN 3
            WHEN total_value_2024 >= 500000000   THEN 2
            ELSE 1
        END                                 AS value_score,
        CASE
            WHEN (total_permits_2024 - permits_2023)::FLOAT
                 / NULLIF(permits_2023, 0) >= 0.15  THEN 3
            WHEN (total_permits_2024 - permits_2023)::FLOAT
                 / NULLIF(permits_2023, 0) >= 0.05  THEN 2
            ELSE 1
        END                                 AS growth_score
    FROM area_metrics
)
SELECT
    community_area,
    total_permits_2024,
    ROUND(total_value_2024 / 1000000.0, 1)  AS value_millions,
    new_construction_pct,
    volume_yoy_pct,
    (new_construction_score + value_score + growth_score)
                                            AS demand_signal_score,
    CASE
        WHEN (new_construction_score + value_score + growth_score) >= 8
            THEN 'High'
        WHEN (new_construction_score + value_score + growth_score) >= 6
            THEN 'Moderate'
        ELSE 'Watch'
    END                                     AS demand_signal
FROM scored
ORDER BY demand_signal_score DESC, total_value_2024 DESC;
