# Phase 5 — Scalability Report

**Project:** MakeMyTrip Travel Booking Database

**Audit date:** 23 November 2026

**Measured seed source:** [`benchmarks/results/optimized/summary.csv`](../benchmarks/results/optimized/summary.csv)

**Optimized workload:** [`sql/06_optimized_queries.sql`](../sql/06_optimized_queries.sql)

**Indexes and summaries:** [`sql/05_indexes.sql`](../sql/05_indexes.sql)

> **Evidence status:** All 12 supplied large CSVs (10,439,710 data rows) are
> loaded in `mmt_large`; their row counts match the supplied files. The optimized
> 30-query workload was measured three times per query and its 90 raw runs are
> retained under [`benchmarks/results/large/`](../benchmarks/results/large/).
> `sql/08_partitioning.sql` was executed: its partitioned copy matches the
> 2,897,285 source bookings, and a static June 2026 plan scanned only the June
> partition. The large run used PostgreSQL 18.6, whereas the seed optimized
> figures used PostgreSQL 16.15; the ratios below are descriptive, not a
> controlled estimate of data-size-only growth.

---

## 1. Executive Summary

The large-data run completed, with one measured latency-target miss: R07 takes
8.332 ms against the 5 ms real-time target. The remaining 29 queries meet their
assigned average-latency targets, though W05 has little headroom at 202.403 ms
against its 250 ms limit.

- The sum of large-workload query averages is **2,569.183 ms** (2,362.101 ms
  reads; 207.082 ms writes). These are serial per-query averages, not a
  wall-clock end-to-end workload duration.
- The large CSV contains **10,439,710 rows** across 12 tables, including
  2,897,285 bookings. All table counts match the supplied dataset.
- The run used **PostgreSQL 18.6** (128 MB `shared_buffers`, 4 MB `work_mem`,
  4 GB `effective_cache_size`, 2 parallel workers, `random_page_cost = 4.0`).
  The seed optimized measurements used PostgreSQL 16.15, so comparisons are
  useful context but do not isolate the effect of dataset size.
- The partitioned copy matched all 2,897,285 bookings. The June plan scanned
  only `bookings_p_2026_06` (159,312 rows; 2,096 shared-buffer reads; 43.750 ms).
- A deliberately pessimistic `seed time × 20` envelope leaves the slowest
  interactive query at **78.800 ms** against a 250 ms target, the slowest report
  at **375.040 ms** against a 5,000 ms target, and the batch update at
  **16.500 ms** against a 1,000 ms target. This is encouraging, but it is a
  sensitivity calculation—not a substitute for measurement.
- The large averages show R07 missing the 5 ms target while W01–W03 remain
  below it. The serial benchmark does not establish concurrent throughput,
  lock behavior, or tail latency.
- The large database measured **1,704 MB** before creating the partition copy,
  and **2,712 MB** afterward. The extra space is the partitioned experiment
  copy, key registry, and their indexes; it is not part of the 30-query
  benchmark's source workload.
- Remaining issues after the large run:
  1. The committed optimized workload still contains a seed-specific R22 cursor;
     the large benchmark used an ephemeral workload with a derived cursor and
     verified its result against `OFFSET`.
  2. R08, R17, R21, and R25 use open-ended date predicates despite describing a
     bounded month or year; R17 also filters booking time rather than trip start.
  3. R14 and R16 are fast because they read materialized views, but their full
     refresh time and freshness lag have not been measured.
  4. The benchmark is single-session and reports averages; it does not prove
     throughput, p95/p99 latency, lock behavior, or protection from overselling.

**Current verdict:** the measured dataset is largely within the stated latency
targets, but R07 misses its target, W05 is close to its limit, and the test does
not prove concurrency or a production partitioned migration. The PostgreSQL
version mismatch also limits seed-to-large growth conclusions.

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

The supplied large dataset was counted directly from its CSV files. Its core
transaction tables are approximately 20× the seed counts: customers 800,000;
bookings 2,897,285; flight bookings 1,698,936; passengers 3,272,394;
hotel bookings 1,198,349. The 100× values are capacity-planning envelopes, not
measured row counts.

**Supplied large CSV row counts (excluding header rows):**

| Table | Large rows |
|---|---:|
| airports | 16 |
| airlines | 5 |
| flights | 13,848 |
| hotels | 60,000 |
| room_types | 180,000 |
| customers | 800,000 |
| coupons | 30 |
| bookings | 2,897,285 |
| flight_bookings | 1,698,936 |
| passengers | 3,272,394 |
| hotel_bookings | 1,198,349 |
| hotel_reviews | 318,847 |

The large `bookings.csv` date range is 1 January 2025 through 30 June 2026
(local offset +05:30). The CSV files belong in the project-root `large_data/`
folder and must remain untracked; `.gitignore` already excludes `large_data/`.

### 2.2 Benchmark protocol already represented in the repository

- Seed optimized measurements: PostgreSQL 16.15 on an Apple M4 with 16 GB
  unified memory; five-run averages, as documented in the Phase 4 report.
- Large measurements: PostgreSQL 18.6 on this Apple Silicon host with 16 GB
  unified memory and the settings listed above; three-run averages.
- `EXPLAIN (ANALYZE, BUFFERS)` was captured for every run. Results are in
  [`benchmarks/results/large/summary.csv`](../benchmarks/results/large/summary.csv)
  and the adjacent per-query plan files.
- The differing PostgreSQL versions and run counts mean the large ÷ seed ratios
  are indicative only. A strict growth comparison requires rerunning both
  datasets on the same PostgreSQL version, host, settings, and cache policy.
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

Large averages come from three actual `EXPLAIN (ANALYZE, BUFFERS)` runs in the
large summary. Growth is `large average ÷ optimized seed average`; it is
descriptive because the PostgreSQL versions differ.

| Query | Optimized seed (ms) | Optimized large (ms) | Growth | Target | Large target status | Scale action / concern |
|---|---:|---:|---:|---:|:---:|---|
| R01 | 0.119 | 3.271 | 27.49× | <5 | Pass | 3.271 ms; inspect route fan-out and repeat on the seed's PostgreSQL version. |
| R02 | 0.069 | 0.221 | 3.20× | <5 | Pass | Range index remains fast. |
| R03 | 0.092 | 0.263 | 2.86× | <5 | Pass | Partial covering index and `LIMIT 20` remain bounded. |
| R04 | 0.202 | 0.352 | 1.74× | <5 | Pass | Hotel-scoped index access remains fast. |
| R05 | 0.133 | 0.177 | 1.33× | <5 | Pass | Customer-scoped partial index remains fast. |
| R06 | 0.091 | 0.183 | 2.01× | <5 | Pass | Unique booking-reference lookup remains fast. |
| R07 | 0.355 | 8.332 | 23.47× | <5 | **Fail** | Manifest join returns many passenger rows; optimize and remeasure. |
| R08 | 2.619 | 17.876 | 6.83× | <250 | Pass | Scheduled-flight aggregation remains below target. |
| R09 | 12.177 | 122.195 | 10.03× | <5000 | Pass | June booking join grows with qualifying rows. |
| R10 | 0.040 | 0.096 | 2.40× | <5 | Pass | Partial index returns the delayed-flight set quickly. |
| R11 | 0.054 | 0.513 | 9.50× | <5 | Pass | Pending-payment index remains below target. |
| R12 | 17.705 | 559.456 | 31.60× | <5000 | Pass | 2026 range scan grows; consider monthly rollups/partitioned source. |
| R13 | 0.122 | 1.069 | 8.76× | <250 | Pass | Indexed anti-join remains inexpensive. |
| R14 | 0.055 | 0.112 | 2.04× | <5000 | Pass | Tiny materialized-view read; refresh cost is not measured. |
| R15 | 7.549 | 125.608 | 16.64× | <5000 | Pass | June overlap aggregate grows with stays. |
| R16 | 0.058 | 0.150 | 2.59× | <5000 | Pass | Tiny materialized-view read; refresh cost is not measured. |
| R17 | 18.752 | 650.659 | 34.70× | <5000 | Pass | Large aggregation remains within target; fix semantics and bound dates. |
| R18 | 1.472 | 59.042 | 40.11× | <250 | Pass | GIN candidate/recheck and ordering work grows, but remains within target. |
| R19 | 11.827 | 213.969 | 18.09× | <5000 | Pass | June flight/passenger join remains within target. |
| R20 | 1.618 | 44.167 | 27.30× | <5000 | Pass | Month scan/aggregate grows with qualifying bookings. |
| R21 | 17.009 | 224.945 | 13.23× | <5000 | Pass | Senior-passenger join remains within target; bound the year. |
| R22 | 0.049 | 0.164 | 3.35× | <250 | Pass | Large-specific page-4,000 cursor was derived before timing. |
| R23 | 0.074 | 0.121 | 1.64× | <5 | Pass | Expression-index lookup remains fast. |
| R24 | 3.940 | 59.558 | 15.12× | <250 | Pass | Goa review aggregation grows with reviews but remains below target. |
| R25 | 17.375 | 269.602 | 15.52× | <5000 | Pass | Flight/booking join remains within target; add an upper bound. |
| W01 | 0.491 | 1.678 | 3.42× | <5 | Pass | Rolled-back point insert remains below target. |
| W02 | 0.525 | 1.205 | 2.30× | <5 | Pass | Partial index lookup remains below target; concurrency is untested. |
| W03 | 0.644 | 0.599 | 0.93× | <5 | Pass | Point update remains below target. |
| W04 | 0.825 | 1.197 | 1.45× | <1000 | Pass | Batch update remains below target; WAL/lock impact is untested. |
| W05 | 3.030 | 202.403 | 66.80× | <250 | Pass | Near target; inspect update count and batch if production volume grows. |

### 3.1 Seed target check

All optimized seed averages passed their assigned targets. On the large run,
R07 is the only average above its assigned threshold; W05 is within its 250 ms
limit but has limited headroom. R07's raw plans are in
[`benchmarks/results/large/R07.txt`](../benchmarks/results/large/R07.txt).

---

## 4. Growth Analysis

### 4.1 Observed under 3× growth

Using the observed ratios descriptively (with the cross-version caveat in
Section 2.2), these queries stayed below 3×. Point lookups and bounded reads
generally remain independent of full-table cardinality; R07 is an exception
because it emits a larger manifest and incurs cold-read cost.

| Queries | Observed ratio | Qualification |
|---|---:|---|
| R03, R04, R05, R06, R10, R14, R16, R23, W02, W03, W04 | 0.93×–2.86× | Point, bounded, or small-summary operations; cold-cache and version effects remain. |

### 4.2 Grew 3×–20×

R02, R08, R09, R11, R13, R15, R19, R21, R22, R24, R25, and W01 grew
between 3× and 20× by the summary averages. Most process a larger date slice,
join more rows, or perform more index and heap work. Their absolute latencies
remain below their assigned thresholds.

### 4.3 Grew more than 20×

R01 (27.49×), R07 (23.47×), R12 (31.60×), R17 (34.70×), R18 (40.11×), R20
(27.30×), and W05 (66.80×) exceeded 20× by the seed/large summary ratio. This
does not establish super-linear data growth because the measurements used
different PostgreSQL versions and repeat counts. The plans show these specific
cost drivers:

1. **R01** remains below 5 ms (3.271 ms); the ratio is magnified by its very low
   seed time. Compare under a common server version before changing its index.
2. **R07** misses the 5 ms limit at 8.332 ms. The plan estimates 223 output rows
   and returns 264, with 142 active bookings and 264 passenger rows. The first
   run takes 21.602 ms and reads 520 shared blocks; the warm runs take 1.710 ms
   and 1.684 ms. The average is sensitive to cold-cache behavior. No index/query
   change was made; investigate index-only booking-status access and remeasure
   using a defined cache policy.
3. **R12** scans 884,142 qualifying booking rows and performs an external merge
   sort using 26,720 kB of disk (3,340 temporary blocks read and 3,354 written
   in each warm run). It remains under 5 seconds at 559.456 ms. A monthly
   summary or partitioned/rollup design is a follow-up if this latency is too
   high for the product SLA.
4. **R17, R18, and R20** do broad aggregate, text-match, or monthly scan work.
   R18's first run rechecks 44,568 review rows and produces 6,661 Goa matches
   before the top-30 sort. All three remain within their latency targets.
5. **W05** updates 1,681 rows after examining 1,859 unassigned check-ins and
   performing booking lookups. Its 202.403 ms average is close to the 250 ms
   target; the first run also dirties/writes buffers. Batch the update and
   measure WAL/lock impact before production.
6. **R14/R16 refreshes and concurrency** remain unmeasured; their fast reads do
   not bound the cost of maintaining summaries or handling simultaneous writes.

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

The large run now supplies actual plans. The items below distinguish measured
behavior from remaining acceptance work.

| Risk | Evidence in current project | Large-data acceptance test | Corrective action if observed |
|---|---|---|---|
| R22 returns the wrong page | Seed cursor is not portable | Large run used cursor `(2026-06-12 03:56:17+05:30, 2896507)`, derived from row 100,000; keyset result matched `OFFSET 100000` with zero row differences | Parameterize `(booked_at, booking_id)` as an API cursor; never commit a dataset-specific literal |
| R07 exceeds real-time target | Large plan returns 264 passenger rows; first run reads 520 blocks and takes 21.602 ms, warm runs take about 1.7 ms | Define cold/warm cache acceptance and compare a booking-status covering index under the same three-run protocol | Investigate index-only booking status access or another covering access path; no change made in this task |
| W05 approaches interactive target | 1,681 rows updated; first run 397 ms, warm runs 180 ms and 29.6 ms | Record row count, buffers, WAL, lock time, and p95/p99 in a concurrent batch test | Batch updates and tune only if production measurements justify it |
| Open-ended time scans | R08, R17, R21, R25 have no exclusive upper bound; R17 also filters booking time instead of trip start | Compare counts and plans before/after explicit July/2026 ranges and the corrected R17 travel-date expression | Add sargable half-open ranges and prove equivalence or document the intended correctness fix |
| Hash/sort spill | R17 already showed a small seed spill in Phase 4 analysis | Inspect `Sort Method`, `Batches`, and temp read/write buffers | Use partition pruning, pre-aggregation, or session-local analytics `work_mem`; do not raise global `work_mem` blindly |
| MV maintenance dominates | R14/R16 measure only tiny MV reads | Time `REFRESH MATERIALIZED VIEW CONCURRENTLY` and record WAL/I/O | Refresh on replica/off-peak or replace with incrementally maintained summary tables |
| Index-only scans degrade | Current fast plans rely on visibility-map coverage after `VACUUM ANALYZE` | Record heap fetches after sustained writes, not only after bulk load | Tune autovacuum per hot table/partition and monitor dead tuples/visibility |
| Bad join plan | Seed tables fit easily in memory | Compare estimated vs actual rows for every large plan | Raise per-column statistics and create extended statistics for correlated predicates |
| Payment workers serialize | W02 selects the global minimum pending ID | Run 16–32 concurrent W02 workers and measure lock waits/duplicates | Claim rows with `FOR UPDATE SKIP LOCKED`, or consume a payment queue |
| Inventory overselling | R01/R04 compute availability from aggregates | Run concurrent reserve/confirm transactions against the last seat/room | Use atomic inventory reservations, row locks, or serializable constraints; indexes alone do not enforce capacity |

The R07 and W05 raw plans include row estimates, actual rows, buffers, and
execution times. No post-fix timings exist because this task measured and
documented the misses without changing the workload or index design.

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

### 6.2 Measured large storage

| Item | Measured size |
|---|---:|
| Large database before partition copy | 1,704 MB |
| Large database after partition copy | 2,712 MB |
| `mmt` relation heaps after partition copy | 1,216 MB |
| `mmt` indexes after partition copy | 1,487 MB |
| `mmt` total relation size after partition copy | 2,704 MB |
| Original `bookings` heap / indexes / total | 298 MB / 420 MB / 717 MB |
| `booking_key_registry` heap / indexes / total | 144 MB / 177 MB / 322 MB |

The benchmark workload used the original `mmt.bookings`; the additional roughly
1,008 MB is the partitioned experiment copy and its registry/indexes. Reported
relation sizes use PostgreSQL's rounded display units and do not sum exactly to
the database size.

### 6.3 Capacity envelope, not a measurement

| Item | Seed | Linear 20× envelope | Linear 100× envelope |
|---|---:|---:|---:|
| Optimized database | 96 MB | ≈1.9 GB | ≈9.4 GB |
| Table/MV heaps | 40 MB | ≈800 MB | ≈4.0 GB |
| Phase 4 indexes | 30 MB | ≈600 MB | ≈3.0 GB |
| `bookings` heap | 15 MB | ≈300 MB | ≈1.5 GB |
| Main booking date index | 11 MB | ≈220 MB | ≈1.1 GB |

These estimates assume uniform scaling and similar value widths. The measured
large database before partitioning is 1,704 MB; the partition experiment raises
it to 2,712 MB. B-tree fill factor, GIN posting lists, materialized views,
TOAST data, free space, and bloat affect actual growth. The 100× booking
count—about 14.5 million—is not, by itself, a reason to shard.

### 6.4 Storage query

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

#### Migration DDL sketch

This is a migration design, not a drop-in replacement for the current table.
The executed side-by-side experiment is [`sql/08_partitioning.sql`](../sql/08_partitioning.sql):
it creates monthly partitions covering January 2025 through July 2026, copies
the source bookings, adds the key registry and indexes, and validates equal row
counts.

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

#### Executed partition-pruning proof

```sql
SET enable_partition_pruning = on;

EXPLAIN (ANALYZE, BUFFERS)
SELECT booked_at::date AS day, count(*)
FROM mmt.bookings_partitioned
WHERE booked_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND booked_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
GROUP BY 1;
```

On PostgreSQL 18.6, the query returned 30 daily groups and scanned only
`bookings_p_2026_06`: 159,312 actual rows, 2,096 shared-buffer reads, and
43.750 ms execution time. No other monthly partition appeared in the static
plan. The SQL script's dynamic latest-month check also matched all
2,897,285 source and partitioned rows and executed only the June partition.
This proves pruning on the experiment copy; the 30-query workload still targets
the original unpartitioned `mmt.bookings`, so these benchmark timings are not
partitioned-table timings.

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

1. R07 averages 8.332 ms, above its 5 ms target; no query/index fix was made.
   W05 averages 202.403 ms, below but close to its 250 ms target.
2. The seed/large comparison uses PostgreSQL 16.15 and 18.6 respectively, so
   ratios do not isolate data-size growth.
3. R08, R17, R21, and R25 need bounded time semantics for future data; R17's
   “trips that started” description also does not match its `booked_at` filter.
4. Materialized-view refresh time/freshness and concurrent inventory/payment
   behavior remain unmeasured.
5. The large database was already populated when this run began; counts and
   indexes were verified, but source input hashes were not recorded here.
6. The range-partitioned table is an experiment copy. Replacing `mmt.bookings`
   requires coordinating child foreign keys and global key uniqueness.

---

## 10. Completion and Acceptance Checklist

1. **Done:** verified all 12 loaded CSV row counts. Input hashes remain to be
   recorded.
2. **Verified pre-existing:** `mmt_large` contains the large dataset and all
   Phase 4 indexes. This task did not recreate the database or run the load
   script again.
3. **Done:** captured PostgreSQL 18.6 settings and measured three runs for each
   optimized query; all 30 raw plan files and the summary are retained.
4. **Done for R22:** derived cursor `(2026-06-12 03:56:17+05:30, 2896507)`
   outside the timed query and confirmed its 25 rows match `OFFSET 100000`.
   R08, R17, R21, and R25 still need bounded/corrected date semantics.
5. **Done:** populated Section 3 and analyzed the only target miss (R07), as
   well as the >20× summary ratios. No performance fix was made.
6. **Done:** recorded large database, heap, index, and partition-experiment
   storage measurements in Section 6.
7. **Done:** executed `sql/08_partitioning.sql`, verified row-count equality,
   and recorded the actual June pruning plan in Section 7.
8. **Remaining:** measure concurrent materialized-view refresh duration and
   agree on a freshness SLA.
9. **Remaining:** run concurrency tests for checkout, payment claiming,
   cancellation, seat inventory, and room inventory; report p95/p99 and lock
   waits.
10. **Remaining:** repeat seed and large runs on the same PostgreSQL version,
    host, settings, and cache policy to produce controlled growth ratios.

### Final acceptance gates

- R07 must be optimized to meet 5 ms or receive an evidence-backed exception.
- W05 must retain margin below its 250 ms limit under the agreed cache/load
  protocol.
- Growth ratios must be remeasured under matching database environments before
  asserting super-linear growth.
- R22 returns the correct page on large data.
- R14/R16 refresh within the agreed freshness window without unacceptable
  primary load or replica lag.
- Partition pruning is demonstrated, not assumed.
- Concurrency tests show no duplicate claims or inventory overselling.

---

## 11. Conclusion

The large-data experiment and three-run benchmark are complete. Twenty-nine
queries meet their specified average-latency targets, and R22's large-data
keyset page was verified against the offset result. Monthly pruning was
demonstrated on the partitioned experiment copy.

The database is **not yet proven ready for production growth**: R07 misses its
real-time target, W05 has limited margin, and the seed/large ratio is not a
controlled comparison because PostgreSQL versions differ. The partitioned
copy also does not replace the original table's foreign-key and global
uniqueness semantics. Refresh cost, concurrency, and future time-window
correctness remain open. Sharding should remain a later throughput/availability
decision rather than a response to the measured storage size alone.
