-- sql/01_staging.sql
-- ---------------------------------------------------------------
-- Staging table DDL for Chicago Building Permits dataset
-- Source: data.cityofchicago.org (Socrata API, dataset: ydr8-5enu)
-- ---------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS chicago_permits;

CREATE TABLE IF NOT EXISTS stg.chicago_permits (
    permit_id           VARCHAR(50)     PRIMARY KEY,
    permit_type         VARCHAR(100),
    work_type           VARCHAR(100),
    issue_date          DATE,
    estimated_cost      DECIMAL(15, 2),
    community_area      INT,
    ward                INT,
    street_number       VARCHAR(20),
    street_direction    VARCHAR(5),
    street_name         VARCHAR(100),
    suffix              VARCHAR(20),
    latitude            DECIMAL(10, 7),
    longitude           DECIMAL(10, 7),
    xcoordinate         DECIMAL(12, 2),
    ycoordinate         DECIMAL(12, 2),
    loaded_at           TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_issue_date
    ON stg.chicago_permits (issue_date);

CREATE INDEX IF NOT EXISTS idx_community_area
    ON stg.chicago_permits (community_area);

CREATE INDEX IF NOT EXISTS idx_work_type
    ON stg.chicago_permits (work_type);

CREATE INDEX IF NOT EXISTS idx_ward
    ON stg.chicago_permits (ward);
