-- sql/03_community_area.sql
-- ---------------------------------------------------------------
-- Neighborhood-level permit aggregations
-- Produces the community area ranking table used in the dashboard
-- ---------------------------------------------------------------

WITH annual_area AS (
    SELECT
        community_area,
        EXTRACT(YEAR FROM issue_date)                   AS permit_year,
        COUNT(*)                                        AS total_permits,
        SUM(estimated_cost)                             AS total_value,
        COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')
                                                        AS new_construction,
        ROUND(
            COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')::FLOAT
            / NULLIF(COUNT(*), 0) * 100, 2
        )                                               AS new_construction_pct
    FROM stg.chicago_permits
    WHERE issue_date IS NOT NULL
      AND community_area IS NOT NULL
    GROUP BY 1, 2
),
with_yoy AS (
    SELECT
        *,
        LAG(total_permits) OVER (
            PARTITION BY community_area
            ORDER BY permit_year
        )                                               AS prior_yr_permits,
        LAG(total_value) OVER (
            PARTITION BY community_area
            ORDER BY permit_year
        )                                               AS prior_yr_value
    FROM annual_area
),
ranked AS (
    SELECT
        *,
        ROUND(
            (total_permits - prior_yr_permits)::FLOAT
            / NULLIF(prior_yr_permits, 0) * 100, 2
        )                                               AS permit_yoy_pct,
        ROUND(
            (total_value - prior_yr_value)::FLOAT
            / NULLIF(prior_yr_value, 0) * 100, 2
        )                                               AS value_yoy_pct,
        RANK() OVER (
            PARTITION BY permit_year
            ORDER BY total_permits DESC
        )                                               AS volume_rank,
        RANK() OVER (
            PARTITION BY permit_year
            ORDER BY total_value DESC
        )                                               AS value_rank
    FROM with_yoy
)
SELECT
    community_area,
    permit_year,
    total_permits,
    ROUND(total_value / 1000000.0, 2)                  AS value_millions,
    new_construction_pct,
    permit_yoy_pct,
    value_yoy_pct,
    volume_rank,
    value_rank
FROM ranked
WHERE permit_year = 2024
ORDER BY volume_rank
LIMIT 20;
