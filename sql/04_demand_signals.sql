-- sql/04_demand_signals.sql
-- ---------------------------------------------------------------
-- Materials demand signal scoring by community area
--
-- Context: New construction consumes 3 to 4x more raw materials
-- per square foot than renovation. Scoring areas by their mix of
-- new construction, total value, and YoY growth gives a building
-- materials supplier a 6 to 9 month forward demand view.
-- ---------------------------------------------------------------

WITH base AS (
    SELECT
        community_area,
        COUNT(*)                                        AS permits_2024,
        SUM(estimated_cost)                             AS value_2024,
        COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')
                                                        AS new_construction_2024,
        ROUND(
            COUNT(*) FILTER (WHERE work_type = 'NEW CONSTRUCTION')::FLOAT
            / NULLIF(COUNT(*), 0) * 100, 2
        )                                               AS new_construction_pct
    FROM stg.chicago_permits
    WHERE EXTRACT(YEAR FROM issue_date) = 2024
      AND community_area IS NOT NULL
    GROUP BY community_area
),
prior_year AS (
    SELECT
        community_area,
        COUNT(*)                                        AS permits_2023
    FROM stg.chicago_permits
    WHERE EXTRACT(YEAR FROM issue_date) = 2023
      AND community_area IS NOT NULL
    GROUP BY community_area
),
combined AS (
    SELECT
        b.*,
        p.permits_2023,
        ROUND(
            (b.permits_2024 - p.permits_2023)::FLOAT
            / NULLIF(p.permits_2023, 0) * 100, 2
        )                                               AS volume_yoy_pct
    FROM base b
    LEFT JOIN prior_year p USING (community_area)
),
scored AS (
    SELECT
        *,
        CASE
            WHEN new_construction_pct >= 35 AND permits_2024 >= 1500 THEN 3
            WHEN new_construction_pct >= 25 AND permits_2024 >= 1000 THEN 2
            ELSE 1
        END                                             AS new_construction_score,
        CASE
            WHEN value_2024 >= 1000000000 THEN 3
            WHEN value_2024 >= 500000000  THEN 2
            ELSE 1
        END                                             AS value_score,
        CASE
            WHEN volume_yoy_pct >= 15 THEN 3
            WHEN volume_yoy_pct >= 5  THEN 2
            ELSE 1
        END                                             AS growth_score
    FROM combined
)
SELECT
    community_area,
    permits_2024,
    ROUND(value_2024 / 1000000.0, 1)                  AS value_millions,
    new_construction_pct,
    volume_yoy_pct,
    (new_construction_score + value_score + growth_score)
                                                        AS demand_score,
    CASE
        WHEN (new_construction_score + value_score + growth_score) >= 8 THEN 'High'
        WHEN (new_construction_score + value_score + growth_score) >= 6 THEN 'Moderate'
        ELSE 'Watch'
    END                                                 AS demand_signal
FROM scored
ORDER BY demand_score DESC, value_2024 DESC;
