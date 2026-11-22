# Phase 5 — Scalability Report

**Project:** MakeMyTrip Travel Booking Database

**Audit date:** 22 November 2026

**Measured seed source:** [`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv)

**Optimized workload:** [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql)

**Indexes and summaries:** [`sql/05_indexes.sql`](../sql/05_indexes.sql)

> **Evidence status:** This repository does not currently contain `large_data/`,
> `large_data.zip`, `benchmarks/results/large/`, or `sql/08_partitioning.sql`.
> Therefore, every large-dataset timing and growth factor below is marked **not
> measured**. No timing has been invented. This document provides the complete
> evidence-backed seed baseline, scale-risk analysis, 100× architecture, and the
> exact acceptance work needed to finish the large-data round.

---

## 1. Executive Summary

The Phase 4 design is a strong starting point for 20× growth, but the database
cannot yet be declared ready for next year because the required large-data run is
missing.

- The optimized 30-query seed workload totals **119.071 ms**, down from
  **1,515.476 ms** at baseline: a **92.14% reduction (12.73× faster)**.
- All 30 optimized seed averages meet their applicable Phase 5 latency targets.
- The repository contains **150 optimized raw runs** (30 queries × 5 runs) and
  **90 baseline raw runs** (30 × 3 runs). The published totals reconcile with the
  two summary CSV files.
- A deliberately pessimistic `seed time × 20` envelope leaves the slowest
  interactive query at **78.800 ms** against a 250 ms target, the slowest report
  at **375.040 ms** against a 5,000 ms target, and the batch update at
  **16.500 ms** against a 1,000 ms target. This is encouraging, but it is a
  sensitivity calculation—not a substitute for measurement.
- Real-time point operations should grow approximately with B-tree height rather
  than row count. If they unexpectedly grew linearly, R07 and W01–W03 could miss
  the 5 ms target; those paths require actual 20× measurements.
- The optimized seed database is **96 MB**, compared with **67 MB** before
  optimization. A simple linear storage envelope is about **1.9 GB at 20×** and
  **9.4 GB at 100×**. Actual size must be captured after the large load.
- Four issues must be addressed during the large round:
  1. R22's hard-coded seed cursor does not identify page 4,001 on a different
     dataset.
  2. R08, R17, R21, and R25 use open-ended date predicates despite describing a
     bounded month or year; R17 also filters booking time rather than trip start.
  3. R14 and R16 are fast because they read materialized views, but their full
     refresh time and freshness lag have not been measured.
  4. The benchmark is single-session and reports averages; it does not prove
     throughput, p95/p99 latency, lock behavior, or protection from overselling.

**Current verdict:** likely capable of the stated 20× volume based on plan shape
and target margin, but **not yet proven**. Final acceptance requires the large
benchmark, actual plans, storage measurements, and the corrections listed in
Section 10.

---

## 2. Scope, Dataset, and Method

### 2.1 Seed scale and expected scale

| Item | Seed rows | Expected 20× rows | 100× planning envelope |
|---|---:|---:|---:|
| Customers | 40,000 | ≈800,000 | ≈4,000,000 |
| Bookings | 144,792 | ≈2,895,840 | ≈14,479,200 |
| Flight bookings | 84,899 | ≈1,697,980 | ≈8,489,900 |
| Passengers | 163,380 | ≈3,267,600 | ≈16,338,000 |
| Hotel bookings | 59,893 | ≈1,197,860 | ≈5,989,300 |
| All 12 tables | 534,776 | ≈10.7 million if all scale uniformly | ≈53.5 million |

The 20× values are the faculty-specified approximate scale. The 100× values are
capacity-planning envelopes, not measured row counts.

### 2.2 Benchmark protocol already represented in the repository

- PostgreSQL 16.15 on an Apple M4 with 16 GB unified memory for the optimized
  run, using the default settings documented in the Phase 4 report.
- `EXPLAIN (ANALYZE, BUFFERS)` for each query.
- Seed optimized figures are five-run averages; the Phase 5 requirement is a
  three-run average. The final comparison should use the same PostgreSQL binary,
  host, settings, and cache policy for both datasets.
- Writes run inside `BEGIN ... ROLLBACK`, so the latency is measured without
  permanently changing the data.
- The current method is a serial latency benchmark. It does not model concurrent
  checkout, payment callbacks, cancellations, or inventory contention.

### 2.3 Performance targets

| Workload class | Queries | Required average |
|---|---|---:|
| Real-time / customer-facing | R01, R02, R03, R04, R05, R06, R07, R10, R11, R23, W01, W02, W03 | **< 5 ms** |
| Interactive partner tools | R08, R13, R18, R22, R24, W05 | **< 250 ms** |
| Reports and analytics | R09, R12, R14, R15, R16, R17, R19, R20, R21, R25 | **< 5,000 ms** |
| Batch jobs | W04 | **< 1,000 ms** |

---

## 3. Required 30-Query Results Table

`Large (ms)`, `growth`, and large target status must be populated only from
`benchmarks/results/large/summary.csv`. Until that evidence exists, the correct
status is **unverified**.

| Query | Optimized seed (ms) | Optimized large (ms) | Growth | Target | Large target status | Scale action / concern |
|---|---:|---:|---:|---:|:---:|---|
| R01 | 0.119 | Not measured | — | <5 | Unverified | Measure route/day fan-out and inventory aggregation. |
| R02 | 0.069 | Not measured | — | <5 | Unverified | Range index is suitable; matching monthly flights may grow with volume. |
| R03 | 0.092 | Not measured | — | <5 | Unverified | Partial covering index plus `LIMIT 20` should remain bounded. |
| R04 | 0.202 | Not measured | — | <5 | Unverified | Validate overlap selectivity and rooms-per-hotel distribution. |
| R05 | 0.133 | Not measured | — | <5 | Unverified | Customer-scoped partial index should scale with trips per customer. |
| R06 | 0.091 | Not measured | — | <5 | Unverified | Unique booking-reference lookup should be logarithmic. |
| R07 | 0.355 | Not measured | — | <5 | Unverified | Validate passengers per flight; linear 20× growth would miss target. |
| R08 | 2.619 | Not measured | — | <250 | Unverified | Add an upper bound for July 2026 before testing future-horizon data. |
| R09 | 12.177 | Not measured | — | <5000 | Unverified | Month-scoped fact join should grow near qualifying row count. |
| R10 | 0.040 | Not measured | — | <5 | Unverified | Partial index is strong; result size depends on active delayed flights. |
| R11 | 0.054 | Not measured | — | <5 | Unverified | Sparse partial index should remain fast; verify pending-queue cardinality. |
| R12 | 17.705 | Not measured | — | <5000 | Unverified | Year scan is a partitioning and summary-table candidate. |
| R13 | 0.122 | Not measured | — | <250 | Unverified | Thirty indexed anti-join probes should remain almost constant. |
| R14 | 0.055 | Not measured | — | <5000 | Unverified | Record both query latency and materialized-view refresh duration. |
| R15 | 7.549 | Not measured | — | <5000 | Unverified | Date-overlap scan should grow with June stays. |
| R16 | 0.058 | Not measured | — | <5000 | Unverified | Record both query latency and materialized-view refresh duration. |
| R17 | 18.752 | Not measured | — | <5000 | Unverified | Bound 2026, verify the intended “trip start” field, and watch temp spill. |
| R18 | 1.472 | Not measured | — | <250 | Unverified | GIN candidates may grow 20× before the top-30 sort. |
| R19 | 11.827 | Not measured | — | <5000 | Unverified | Join rewrite is sound; workload grows with June flights/passengers. |
| R20 | 1.618 | Not measured | — | <5000 | Unverified | Month range should benefit directly from partition pruning. |
| R21 | 17.009 | Not measured | — | <5000 | Unverified | Add `< 2027-01-01`; current predicate is open-ended. |
| R22 | 0.049 | Not measured | — | <250 | Unverified | Replace the seed cursor with the large dataset's page-4,000 cursor. |
| R23 | 0.074 | Not measured | — | <5 | Unverified | Expression index lookup should be logarithmic. |
| R24 | 3.940 | Not measured | — | <250 | Unverified | Review aggregation may become scan- or spill-bound at scale. |
| R25 | 17.375 | Not measured | — | <5000 | Unverified | Add an upper 2027 bound and inspect the large join plan. |
| W01 | 0.491 | Not measured | — | <5 | Unverified | Point insert should be logarithmic; production needs sequence-generated IDs. |
| W02 | 0.525 | Not measured | — | <5 | Unverified | Partial index is strong; use `SKIP LOCKED` under concurrent workers. |
| W03 | 0.644 | Not measured | — | <5 | Unverified | Measure index maintenance and status-change contention. |
| W04 | 0.825 | Not measured | — | <1000 | Unverified | Measure rows changed, WAL, locks, and batching—not latency alone. |
| W05 | 3.030 | Not measured | — | <250 | Unverified | Expected to grow with same-day check-ins; batch if lock time rises. |

### 3.1 Seed target check

All optimized seed averages pass their assigned targets. This confirms the index
and rewrite design on 144,792 bookings, not on the expected 2.9 million bookings.

---

## 4. Growth Analysis

### 4.1 Expected to stay about the same

These operations are point lookups, bounded result queries, or reads from tiny
pre-aggregated relations. Their cost should grow approximately as `O(log n)` or
with a stable per-entity row count, not with the whole database.

| Queries | Why growth should be small | Qualification |
|---|---|---|
| R03 | Partial index ordered for `LIMIT 20` | Assumes pool-equipped Goa hotels do not overwhelm the filter. |
| R04, R05, R07 | One hotel, customer, or flight | Stable only if rows per entity remain comparable. |
| R06, R23 | One B-tree/expression-index lookup | Larger B-trees may add one level and more cache misses. |
| R13 | At most 30 indexed coupon probes | Coupon catalogue is fixed and small. |
| R14, R16 | Read 5 or 8 materialized rows | The hidden refresh work grows with base data. |
| R22 | 25-row keyset page | Only if the correct cursor is supplied. |
| W01, W02, W03 | One insert or point update | Index maintenance is logarithmic; concurrency may dominate. |

### 4.2 Expected to grow roughly with the qualifying data

| Queries | Main scaling term |
|---|---|
| R01, R02 | Flights and booked passengers in the selected route/date range. |
| R08, R09 | Scheduled flights or June flight bookings being grouped. |
| R10, R11 | Number of active delayed flights or old pending payments returned. |
| R12, R17, R20 | Booking rows in a year/month plus aggregation. |
| R15 | Hotel stays overlapping June plus active-booking checks. |
| R18 | Trigram matches that must be rechecked and ordered before `LIMIT 30`. |
| R19, R21, R25 | Qualifying flight, passenger, and booking join rows. |
| R24 | Goa review rows grouped per hotel. |
| W04, W05 | Rows actually updated, WAL generated, and indexes maintained. |

### 4.3 Risks that can grow more than 20×

No query can yet be placed in the observed “more than 20×” category because the
large plans do not exist. The following are the audited candidates:

1. **R08, R17, R21, and R25 — expanding time horizon.** Their descriptions refer
   to July or 2026, but their SQL has only a lower date bound. R17 additionally
   says “trips that started” while filtering `booked_at`. Additional future years
   can make the qualifying share grow faster than the dataset multiplier and can
   also change the answer.
2. **R17 and R24 — memory threshold changes.** A hash aggregate or sort that fits
   in memory on seed data may spill to temporary files on large data. Crossing
   that threshold creates a non-linear latency jump.
3. **R18 — large GIN posting lists.** The GIN index finds text matches, but all
   qualifying candidates may still be rechecked and sorted by `created_at` before
   returning 30 rows.
4. **R14 and R16 refreshes.** Query latency remains nearly constant while a full
   materialized-view refresh scans and joins the growing base tables. Reporting
   only the read time would hide the real maintenance cost.
5. **W04 and W05 — write amplification.** Updating 20× more rows can trigger more
   WAL, dirty buffers, checkpoints, index page splits, and lock waits than a
   simple 20× CPU estimate predicts.
6. **Planner misestimation.** Default statistics may miss correlations among
   `booking_type`, `status`, `booked_at`, and join keys, causing an unsuitable
   nested loop or join order only at large scale.

### 4.4 Pessimistic linear sensitivity envelope

This table multiplies only the slowest measured seed query in each target group
by 20. It is a risk screen, not a claimed prediction.

| Group | Slowest seed query | Seed (ms) | Seed × 20 (ms) | Target | Interpretation |
|---|---|---:|---:|---:|---|
| Real-time | W03 | 0.644 | 12.880 | 5 | A linear outcome would fail; point operations are expected to be sublinear and must be measured. |
| Interactive | R24 | 3.940 | 78.800 | 250 | 3.2× target margin even under linear growth. |
| Analytics | R17 | 18.752 | 375.040 | 5,000 | 13.3× target margin, subject to temp-spill and plan changes. |
| Batch | W04 | 0.825 | 16.500 | 1,000 | Large margin, but WAL/lock impact still needs measurement. |

---

## 5. What Can Break at Scale and How to Test It

Because no large run is present, this section records testable failure hypotheses
rather than claiming scale-only failures were observed.

| Risk | Evidence in current project | Large-data acceptance test | Corrective action if observed |
|---|---|---|---|
| R22 returns the wrong page | Cursor `(2025-06-18 22:17:24+05:30, 46410)` came from seed data | Derive row 100,000 from the large ordering outside the timed query; compare the next 25 rows with `OFFSET` once | Parameterize `(booked_at, booking_id)` as an API cursor; never commit a dataset-specific literal |
| Open-ended time scans | R08, R17, R21, R25 have no exclusive upper bound; R17 also filters booking time instead of trip start | Compare counts and plans before/after explicit July/2026 ranges and the corrected R17 travel-date expression | Add sargable half-open ranges and prove equivalence or document the intended correctness fix |
| Hash/sort spill | R17 already showed a small seed spill in Phase 4 analysis | Inspect `Sort Method`, `Batches`, and temp read/write buffers | Use partition pruning, pre-aggregation, or session-local analytics `work_mem`; do not raise global `work_mem` blindly |
| MV maintenance dominates | R14/R16 measure only tiny MV reads | Time `REFRESH MATERIALIZED VIEW CONCURRENTLY` and record WAL/I/O | Refresh on replica/off-peak or replace with incrementally maintained summary tables |
| Index-only scans degrade | Current fast plans rely on visibility-map coverage after `VACUUM ANALYZE` | Record heap fetches after sustained writes, not only after bulk load | Tune autovacuum per hot table/partition and monitor dead tuples/visibility |
| Bad join plan | Seed tables fit easily in memory | Compare estimated vs actual rows for every large plan | Raise per-column statistics and create extended statistics for correlated predicates |
| Payment workers serialize | W02 selects the global minimum pending ID | Run 16–32 concurrent W02 workers and measure lock waits/duplicates | Claim rows with `FOR UPDATE SKIP LOCKED`, or consume a payment queue |
| Inventory overselling | R01/R04 compute availability from aggregates | Run concurrent reserve/confirm transactions against the last seat/room | Use atomic inventory reservations, row locks, or serializable constraints; indexes alone do not enforce capacity |

For every actual target miss, the final report must add the before/after large
plans, buffer counts, row estimates versus actuals, temp I/O, and the post-fix
three-run average.

---

## 6. Storage Analysis

### 6.1 Measured seed storage

| Storage item | Measured size |
|---|---:|
| Baseline database | 67 MB |
| Optimized database | 96 MB |
| Increase from optimization | 29 MB (43.3%) |
| Table and materialized-view heaps | 40 MB |
| Phase 2 PK/unique indexes | 18 MB |
| Phase 4 indexes | 30 MB |
| `bookings` heap | 15 MB |
| `idx_bookings_booked_at_id` | 11 MB (71.4% of the booking heap using unrounded sizes) |

The components are PostgreSQL-reported rounded values, so they do not sum
exactly to the database total.

### 6.2 Capacity envelope, not a measurement

| Item | Seed | Linear 20× envelope | Linear 100× envelope |
|---|---:|---:|---:|
| Optimized database | 96 MB | ≈1.9 GB | ≈9.4 GB |
| Table/MV heaps | 40 MB | ≈800 MB | ≈4.0 GB |
| Phase 4 indexes | 30 MB | ≈600 MB | ≈3.0 GB |
| `bookings` heap | 15 MB | ≈300 MB | ≈1.5 GB |
| Main booking date index | 11 MB | ≈220 MB | ≈1.1 GB |

These estimates assume uniform scaling and similar value widths. B-tree fill
factor, GIN posting lists, materialized views, TOAST data, free space, and bloat
will make actual growth different. The 100× booking count—about 14.5 million—is
still reasonable for one well-managed PostgreSQL instance; size alone does not
justify sharding.

### 6.3 Queries to capture actual large storage

```sql
SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size;

SELECT c.relname,
       pg_size_pretty(pg_relation_size(c.oid)) AS heap_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'mmt'
  AND c.relkind IN ('r', 'p', 'm')
ORDER BY pg_total_relation_size(c.oid) DESC;
```

---

## 7. Architecture for 100×

### 7.1 Partitioning recommendation

**Recommended design:** monthly `RANGE` partitioning of `bookings` by
`booked_at`, with older completed/cancelled partitions detached to cheaper
storage after the retention window.

Why this key:

- R09, R12, R17, R20, R22, and R25 filter or order by booking time.
- Monthly pruning limits scans, indexes, vacuum work, and reindex scope.
- Old data can be archived by detaching whole partitions instead of deleting
  millions of rows and generating bloat.
- `LIST (booking_type)` would create only two uneven partitions and would not
  prune the major time-series reports.
- `HASH (customer_id)` helps My Trips but not retention or month/year analytics;
  it is better treated as a future sharding key than a local partitioning key.

#### Illustrative DDL

This is a migration design, not a drop-in replacement for the current table:

```sql
CREATE TABLE mmt.bookings_partitioned
(
    LIKE mmt.bookings
      INCLUDING DEFAULTS
      INCLUDING CONSTRAINTS
      INCLUDING STORAGE,
    PRIMARY KEY (booking_id, booked_at),
    UNIQUE (booking_ref, booked_at)
) PARTITION BY RANGE (booked_at);

CREATE TABLE mmt.bookings_2025
    PARTITION OF mmt.bookings_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30')
             TO   ('2026-01-01 00:00:00+05:30');

CREATE TABLE mmt.bookings_2026_01
    PARTITION OF mmt.bookings_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30')
             TO   ('2026-02-01 00:00:00+05:30');

-- Create one partition per month and pre-create future partitions.
CREATE TABLE mmt.bookings_default
    PARTITION OF mmt.bookings_partitioned DEFAULT;

CREATE INDEX idx_bookings_p_booked_at_id
    ON mmt.bookings_partitioned (booked_at DESC, booking_id DESC)
    INCLUDE (booking_type, status, total_amount, customer_id, booking_ref);

-- Small global registry for uniqueness and point-lookup routing.
CREATE TABLE mmt.booking_key_registry (
    booking_id  INTEGER PRIMARY KEY,
    booking_ref VARCHAR(20) NOT NULL UNIQUE,
    booked_at   TIMESTAMPTZ NOT NULL
);
```

#### Primary-key and foreign-key rule

PostgreSQL requires every `PRIMARY KEY` or `UNIQUE` constraint on a partitioned
table to include all partition-key columns. Consequently:

- The current `PRIMARY KEY (booking_id)` cannot be preserved unchanged on a
  table partitioned by `booked_at`.
- The current global `UNIQUE (booking_ref)` also cannot be enforced by a normal
  partitioned-table unique index.
- `flight_bookings` and `hotel_bookings` currently reference only `booking_id`;
  a rigorous range-partitioned migration must add `booked_at` to those child
  rows and use composite foreign keys `(booking_id, booked_at)`.
- A small non-partitioned booking-key registry can enforce global
  `booking_id`/`booking_ref` uniqueness and route point lookups. It must be
  written in the same transaction as the partitioned booking row.

If the schema cannot be changed, `HASH (booking_id)` is the lower-disruption
alternative because the existing primary-key column is also the partition key.
It preserves point lookup/FK behavior but provides no month pruning or cheap
time-based archival; `booking_ref` still needs a global registry.

#### Partition-pruning proof to capture

```sql
SET enable_partition_pruning = on;

EXPLAIN (ANALYZE, BUFFERS)
SELECT booked_at::date AS day, count(*)
FROM mmt.bookings_partitioned
WHERE booked_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND booked_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
GROUP BY 1;
```

The submitted plan must show only the June 2026 partition (or report
`Subplans Removed`) and must include actual buffer counts. No executed pruning
plan is available in the current repository.

### 7.2 Sharding decision

At 100×, approximately 14.5 million bookings and a roughly 9.4 GB database are
not, by themselves, reasons to shard PostgreSQL. Partitioning, adequate memory
and storage, connection pooling, replicas, and summaries should be exhausted
first. Sharding becomes justified by write throughput, geographic placement, or
availability requirements.

| Candidate shard key | Advantage | Cross-shard cost | Verdict |
|---|---|---|---|
| `customer_id` hash | R05 My Trips and most customer history stay on one shard; writes distribute evenly | R07/R19 flight manifests, hotel inventory, global W02 queue, and analytics fan out | **Best choice if sharding becomes necessary** |
| `booking_type` | Flight and hotel domain queries separate cleanly | Only two shards, uneven growth, My Trips checks both, shared checkout logic duplicated | Useful service boundary, poor general sharding key |
| Travel/booking date | Month reports and archival are local | Customer history, booking-ref lookup, manifests, and current writes cross shards; newest shard becomes hot | Prefer as local partition key, not shard key |

With 16 customer-hash shards, 20× data averages about **181,000 bookings per
shard** and 100× about **905,000 per shard**. A production design would add:

- A global `booking_ref → shard_id` directory for R06/W03 routing.
- A `flight_id → shard list` directory or a separately maintained manifest read
  model so R07/R19 do not scatter across every customer shard.
- Per-shard payment workers using `FOR UPDATE SKIP LOCKED`; a global “oldest
  pending” query should become a queue/coordinator operation.
- A replica/warehouse that combines shard change streams for R09, R12, R14–R21,
  R24, and R25 instead of running fan-out analytics on OLTP primaries.

### 7.3 Read replicas and caching

| Destination | Queries | Reason / freshness rule |
|---|---|---|
| Primary | R01, R04, R05, R06, R07, R10, R11, R23, W01–W05 | Inventory, payment, support, identity, and every write need current state. |
| Read replica | R08, R09, R12–R21, R24, R25 | Partner/reporting work can tolerate an explicit replica-lag SLA. R14/R16 refresh on the replica if possible. |
| Conditional replica | R22 | Older support pages may use a replica; recent pages should use the primary if support must see just-committed changes. |
| Cache | R02, R03, R08, R13, R14, R16, R18, R24 | Fare calendars/search/rankings/report summaries have bounded keys and can use TTL plus invalidation. |

R01 seat availability and R04 room availability should not rely on a long-lived
cache. If cached at all, use a very short TTL and confirm inventory atomically on
the primary before checkout.

### 7.4 Maintenance and operational settings

1. **Autovacuum:** use lower scale factors on high-write facts and tune per
   partition. A reasonable starting point to validate under load is:

   ```sql
   ALTER TABLE mmt.bookings SET (
       autovacuum_vacuum_scale_factor = 0.02,
       autovacuum_analyze_scale_factor = 0.01,
       autovacuum_vacuum_threshold = 5000,
       autovacuum_analyze_threshold = 5000
   );
   ```

   Monitor `n_dead_tup`, last vacuum/analyze times, heap fetches, and index bloat;
   fixed settings are not a substitute for observation.

2. **Statistics:** after bulk load run `VACUUM (ANALYZE)`. If large plans show
   row-estimate errors, increase statistics on `booked_at`, `status`,
   `booking_type`, `flight_id`, and hotel date columns. Add extended statistics
   for correlated booking columns where justified by the plan.
3. **Archival:** retain operational partitions for a defined period (for example,
   24 months), then detach immutable completed/cancelled partitions, back them up,
   and attach foreign/archive tables for rare historical access.
4. **Summary maintenance:** refresh R14/R16 summaries concurrently on a schedule
   tied to their freshness SLA. At 100×, prefer incremental daily/monthly rollup
   tables or change-data-capture updates over repeated full-history refreshes.
5. **Write control:** batch W04/W05 in bounded chunks if they update many rows;
   monitor WAL volume, replication lag, checkpoint time, and lock duration.
6. **Connection management:** use a pooler and cap active database sessions.
   Throughput testing should include 16, 32, and 64 clients and report p50, p95,
   p99, errors, and lock waits.
7. **Index review:** the main booking index is wide and causes status updates to
   maintain it. Retain it only if large-plan buffer savings justify its write and
   storage cost. Drop duplicate or unused indexes based on `pg_stat_user_indexes`,
   not on seed-only assumptions.

---

## 8. Correctness and Concurrency at Scale

Scalability is not only query speed.

- **Seat and room capacity:** R01 and R04 calculate availability but do not stop
  two simultaneous checkouts from reserving the final unit. Production needs an
  atomic reservation table/counter, appropriate row locking, expiry, and a
  constraint or serializable transaction that prevents negative inventory.
- **Payment claiming:** W02 should be rewritten for workers as:

  ```sql
  WITH next_payment AS (
      SELECT booking_id
      FROM mmt.bookings
      WHERE status = 'PENDING_PAYMENT'
      ORDER BY booking_id
      FOR UPDATE SKIP LOCKED
      LIMIT 1
  )
  UPDATE mmt.bookings b
  SET status = 'CONFIRMED'
  FROM next_payment n
  WHERE b.booking_id = n.booking_id;
  ```

- **Identifier allocation:** W01's hard-coded ID is suitable only for a rolled-
  back benchmark. Production should use `BIGINT GENERATED ... AS IDENTITY`, a
  sequence, or a distributed ID strategy and should generate collision-resistant
  booking references.
- **Materialized-view freshness:** R14/R16 correctness is relative to the last
  refresh, not the latest booking. The report must state and monitor that lag.
- **Pagination:** keyset pagination is stable only with the complete ordering key
  `(booked_at, booking_id)` carried from the preceding page. It does not support
  arbitrary page jumps without a precomputed cursor/index.

---

## 9. Whole-Project Scalability Assessment

### What is already strong

- Normalized relational design with primary keys, foreign keys, checks, and
  appropriate cascade/restrict rules.
- Sargable date rewrites and targeted covering/partial indexes for the main OLTP
  paths.
- Correct repair of R13's `NOT IN`/`NULL` bug.
- Removal of R19's correlated scan and R22's deep `OFFSET` from the timed path.
- Deliberate materialized summaries for lifetime aggregates.
- Raw plans and summary CSVs are retained and reconcile with the Phase 4 report.

### Remaining readiness gaps

1. No faculty large dataset, large raw plans, or large summary is present.
2. The required `sql/08_partitioning.sql` artifact is absent.
3. R22 is tied to the seed dataset's cursor.
4. R08, R17, R21, and R25 need bounded time semantics for future data; R17's
   travel-start meaning also needs clarification/correction.
5. Materialized-view refresh cost and freshness are not reported.
6. The load script hard-codes `seed_data/` and seed expected row counts; the large
   run should use a parameterized data directory and large expected counts.
7. Serial averages do not test concurrent inventory/payment behavior or tail
   latency.
8. Index-only scan performance was measured immediately after vacuum; sustained
   write conditions still need validation.
9. The seed/large comparison must use the same PostgreSQL version and machine;
   earlier baseline and optimized phases used different PostgreSQL versions.

---

## 10. Completion and Acceptance Checklist

1. Place the faculty files in `large_data/` and verify all 12 row counts and input
   hashes.
2. Create a clean database with `sql/01_schema.sql`; load from `large_data/`
   without altering schema semantics.
3. Run `sql/05_indexes.sql`, then `VACUUM (ANALYZE)` and capture server settings.
4. Correct/parameterize R08, R17, R21, R22, and R25, proving intended result
   equivalence or documenting an intentional correctness fix. For R22, derive
   the large dataset cursor outside the timed query.
5. Run exactly three large trials per query with the optimized workload and save
   all 30 plan files plus `benchmarks/results/large/summary.csv`.
6. Populate Section 3 with measured large averages and ratios; classify each
   query as approximately constant, approximately 20×, or more than 20×.
7. For every miss or >20× growth, include before/after plans and explain estimates,
   actual rows, buffers, temp I/O, heap fetches, and chosen fix.
8. Record total database, heap, index, and materialized-view sizes using the SQL in
   Section 6.
9. Time concurrent materialized-view refreshes and state their freshness SLA.
10. Create `sql/08_partitioning.sql`, run its pruning example, and paste the actual
    `EXPLAIN (ANALYZE, BUFFERS)` evidence into this report.
11. Run a separate concurrency test for checkout, payment claiming, cancellation,
    seat inventory, and room inventory. Record p95/p99 and lock waits.

### Final acceptance gates

- Every measured average meets its assigned target or has a documented,
  evidence-backed exception.
- No query has unexplained super-linear growth.
- R22 returns the correct page on large data.
- R14/R16 refresh within the agreed freshness window without unacceptable
  primary load or replica lag.
- Partition pruning is demonstrated, not assumed.
- Concurrency tests show no duplicate claims or inventory overselling.

---

## 11. Conclusion

The current optimization work has excellent seed-data latency and sensible index
design. Analytical queries have large target margins, point lookups use suitable
indexes, and the worst baseline defect—the repeated R19 scan—has been removed.
The design is therefore a credible candidate for 20× growth.

It is **not yet valid to claim that the database is proven ready for next year**:
the required 20× dataset and large benchmark evidence are absent, R22 is not
portable across datasets, several time filters expand into future data, and
concurrency/summary-refresh costs remain unmeasured. Once the Section 10 gates
are completed, the expected outcome is that one partitioned PostgreSQL primary
with a read replica, targeted caching, and maintained rollups will comfortably
serve the stated 20× and 100× data volumes. Sharding should remain a later
throughput/availability decision, not a response to the projected storage size.
