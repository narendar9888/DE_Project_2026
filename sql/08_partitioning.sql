-- MakeMyTrip DBMS Project — Phase 5 monthly partitioning experiment
-- PostgreSQL 15+
-- Prerequisites:
--   1. Run sql/01_schema.sql.
--   2. Load the large CSV dataset into schema mmt (using large_data/).
--   3. Run sql/05_indexes.sql if you are also benchmarking the normal tables.
--
-- This creates a separate partitioned copy of mmt.bookings. It deliberately
-- does NOT replace mmt.bookings because flight_bookings and hotel_bookings
-- currently have foreign keys to the original booking_id primary key.
-- The separate copy lets us test monthly partition pruning without silently
-- breaking the project's existing foreign-key model.

\set ON_ERROR_STOP on
SET search_path TO mmt, public;
SET TIME ZONE 'Asia/Kolkata';

DO $$
BEGIN
    IF to_regclass('mmt.bookings') IS NULL THEN
        RAISE EXCEPTION 'mmt.bookings does not exist. Run sql/01_schema.sql and load the dataset first.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM mmt.bookings LIMIT 1) THEN
        RAISE EXCEPTION 'mmt.bookings is empty. Load the large dataset before running partitioning.';
    END IF;
END
$$;

-- Safe to rerun: these are only the Phase 5 experiment objects.
DROP TABLE IF EXISTS mmt.booking_key_registry CASCADE;
DROP TABLE IF EXISTS mmt.bookings_partitioned CASCADE;

-- A RANGE-partitioned copy. PostgreSQL requires the partition key to be part
-- of a partitioned table's primary/unique key, so the key is composite here.
CREATE TABLE mmt.bookings_partitioned (
    LIKE mmt.bookings INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    PRIMARY KEY (booking_id, booked_at)
) PARTITION BY RANGE (booked_at);

-- Create one monthly partition for every month represented in the loaded
-- dataset, plus one month beyond the maximum date for forward inserts.
DO $$
DECLARE
    first_month TIMESTAMPTZ;
    last_month  TIMESTAMPTZ;
    month_start TIMESTAMPTZ;
    partition_name TEXT;
BEGIN
    SELECT date_trunc('month', min(booked_at)),
           date_trunc('month', max(booked_at))
      INTO first_month, last_month
      FROM mmt.bookings;

    month_start := first_month;
    WHILE month_start <= last_month + INTERVAL '1 month' LOOP
        partition_name := 'bookings_p_' || to_char(month_start, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE mmt.%I PARTITION OF mmt.bookings_partitioned '
            'FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            month_start,
            month_start + INTERVAL '1 month'
        );

        month_start := month_start + INTERVAL '1 month';
    END LOOP;
END
$$;

-- Catch any unexpected timestamp outside the generated monthly range.
CREATE TABLE mmt.bookings_partitioned_default
    PARTITION OF mmt.bookings_partitioned DEFAULT;

-- Preserve global booking_id and booking_ref uniqueness in a small,
-- non-partitioned lookup/registry table. A partitioned UNIQUE constraint
-- cannot enforce these columns globally unless booked_at is included.
CREATE TABLE mmt.booking_key_registry (
    booking_id INTEGER PRIMARY KEY,
    booking_ref VARCHAR(20) NOT NULL UNIQUE,
    booked_at TIMESTAMPTZ NOT NULL
);

INSERT INTO mmt.bookings_partitioned
SELECT * FROM mmt.bookings;

INSERT INTO mmt.booking_key_registry (booking_id, booking_ref, booked_at)
SELECT booking_id, booking_ref, booked_at
FROM mmt.bookings;

CREATE INDEX idx_bookings_partitioned_booked_at
    ON mmt.bookings_partitioned (booked_at DESC, booking_id DESC)
    INCLUDE (booking_type, status, total_amount, customer_id, booking_ref);

CREATE INDEX idx_bookings_partitioned_customer_date
    ON mmt.bookings_partitioned (customer_id, booked_at DESC);

ANALYZE mmt.bookings_partitioned;
ANALYZE mmt.booking_key_registry;

-- Validation: source and partitioned copy must contain the same number of rows.
SELECT
    (SELECT count(*) FROM mmt.bookings) AS source_rows,
    (SELECT count(*) FROM mmt.bookings_partitioned) AS partitioned_rows,
    (SELECT count(*) FROM mmt.bookings)
      = (SELECT count(*) FROM mmt.bookings_partitioned) AS row_counts_match;

-- Partition-pruning evidence for the latest full month in the loaded data.
-- The plan should scan only one monthly partition (or show Subplans Removed).
\echo 'Partition-pruning test for the latest month in the loaded dataset:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', booked_at) AS booking_day, count(*)
FROM mmt.bookings_partitioned
WHERE booked_at >= (
        SELECT date_trunc('month', max(booked_at)) FROM mmt.bookings
      )
  AND booked_at < (
        SELECT date_trunc('month', max(booked_at)) + INTERVAL '1 month'
        FROM mmt.bookings
      )
GROUP BY 1
ORDER BY 1;

-- IMPORTANT FOR THE REPORT:
-- benchmarks/run_benchmark.sh with sql/06_optimized_queries.sql measures the
-- original mmt.bookings table because the existing 30-query workload and its
-- child-table joins reference that table. This script separately demonstrates
-- partition pruning on mmt.bookings_partitioned. Do not label the standard
-- 30-query timings as partitioned-table timings unless the workload is migrated
-- to the partitioned design and its foreign keys are updated as a coordinated
-- schema migration.
