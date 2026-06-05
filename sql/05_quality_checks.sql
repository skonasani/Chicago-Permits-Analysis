-- sql/05_quality_checks.sql
-- ---------------------------------------------------------------
-- Pipeline data quality audit
-- Runs after every load to validate the staging table
-- Results are written to an audit log for monitoring
-- ---------------------------------------------------------------

SELECT
    CURRENT_TIMESTAMP                                   AS audit_run_time,
    'chicago_permits'                                   AS table_name,
    COUNT(*)                                            AS total_rows,

    -- Null checks
    COUNT(*) - COUNT(issue_date)                        AS null_date_count,
    COUNT(*) - COUNT(estimated_cost)                    AS null_cost_count,
    COUNT(*) - COUNT(community_area)                    AS null_community_area_count,
    COUNT(*) - COUNT(work_type)                         AS null_work_type_count,

    -- Invalid value checks
    SUM(CASE WHEN estimated_cost <= 0 THEN 1 ELSE 0 END)
                                                        AS invalid_cost_count,
    SUM(CASE WHEN issue_date > CURRENT_DATE THEN 1 ELSE 0 END)
                                                        AS future_date_count,
    SUM(CASE WHEN community_area NOT BETWEEN 1 AND 77 THEN 1 ELSE 0 END)
                                                        AS invalid_community_area_count,

    -- Duplicate check
    COUNT(*) - COUNT(DISTINCT permit_id)                AS duplicate_permit_ids,

    -- Freshness check
    MAX(issue_date)                                     AS most_recent_permit_date,
    DATEDIFF('day', MAX(issue_date), CURRENT_DATE)      AS days_since_last_record,
    CASE
        WHEN DATEDIFF('day', MAX(issue_date), CURRENT_DATE) <= 90  THEN 'pass'
        WHEN DATEDIFF('day', MAX(issue_date), CURRENT_DATE) <= 180 THEN 'warn'
        ELSE 'fail'
    END                                                 AS freshness_status,

    -- Year distribution check
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM issue_date) = 2024) AS permits_2024,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM issue_date) = 2023) AS permits_2023,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM issue_date) = 2022) AS permits_2022

FROM stg.chicago_permits;
