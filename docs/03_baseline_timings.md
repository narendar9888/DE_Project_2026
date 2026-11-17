# Phase 3 — Baseline Query Timings

**Project:** MakeMyTrip Travel Booking Database  
**Database:** `mmt_baseline` (schema `mmt`)  
**Workload:** Unaltered `queries/workload_30.sql` (25 READ, 5 WRITE statements)  
**Source Evidence:** `benchmarks/results/baseline/summary.csv` and all 30 raw execution plan files (`R01.txt`–`R25.txt`, `W01.txt`–`W05.txt`)  

---

### Hardware, Operating System, and Engine Environment

- **Machine & Architecture:** Apple Mac; PostgreSQL build targets Apple Silicon (`aarch64-apple-darwin23.6.0`).
- **CPU Model:** Not independently verified (check with `sysctl -n machdep.cpu.brand_string`).
- **System Memory (RAM):** Not independently verified (check with `sysctl -n hw.memsize`).
- **Operating System:** macOS (running kernel version not verified; check with `uname -r`).
- **PostgreSQL Version:** PostgreSQL 18.4 (Postgres.app, 64-bit; confirmed by `SELECT version();`).
- **Key PostgreSQL Configuration Settings (draft values, **not independently verified** against the running baseline database; verify using `pg_settings` before submission):**
  - `shared_buffers`: `128MB` (16,384 x 8kB buffers)
  - `work_mem`: `4MB` (4,096 kB per sort/hash operation)
  - `maintenance_work_mem`: `64MB` (65,536 kB)
  - `effective_cache_size`: `4GB` (524,288 x 8kB pages)
  - `max_parallel_workers_per_gather`: `2`
  - `random_page_cost`: `4.0`
  - `seq_page_cost`: `1.0`
  - `default_statistics_target`: `100`

  Verify the actual values with:
  ```sql
  SELECT name, setting, unit
  FROM pg_settings
  WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem',
                 'effective_cache_size', 'max_parallel_workers_per_gather',
                 'random_page_cost', 'seq_page_cost',
                 'default_statistics_target')
  ORDER BY name;
  ```

### Verified Database Table Sizes (Baseline)

The database was populated using `seed_data/` and verified with `sql/02_load_data.sql`:

| Table Name | Row Count | Primary Key / Unique Indexes Present |
|---|---:|---|
| `mmt.bookings` | 144,792 | `bookings_pkey` (`booking_id`), `bookings_booking_ref_key` (`booking_ref`) |
| `mmt.passengers` | 163,380 | `passengers_pk` (`booking_id`, `seq_no`) |
| `mmt.flight_bookings` | 84,899 | `flight_bookings_pkey` (`booking_id`) |
| `mmt.hotel_bookings` | 59,893 | `hotel_bookings_pkey` (`booking_id`), `hotel_bookings_id_hotel_uq` (`booking_id`, `hotel_id`) |
| `mmt.customers` | 40,000 | `customers_pkey` (`customer_id`) |
| `mmt.hotel_reviews` | 15,913 | `hotel_reviews_pkey` (`review_id`) |
| `mmt.flights` | 13,848 | `flights_pkey` (`flight_id`) |
| `mmt.room_types` | 9,000 | `room_types_pkey` (`room_type_id`), `room_types_id_hotel_uq` (`room_type_id`, `hotel_id`) |
| `mmt.hotels` | 3,000 | `hotels_pkey` (`hotel_id`) |
| `mmt.coupons` | 30 | `coupons_pkey` (`coupon_code`) |
| `mmt.airports` | 16 | `airports_pkey` (`iata_code`) |
| `mmt.airlines` | 5 | `airlines_pkey` (`airline_code`) |

---

## 1. Methodology and Measurement Ground Rules

1. **Unaltered Baseline Workload:** Executed the supplied 30-query workload in `queries/workload_30.sql` (25 READ and 5 WRITE statements) without modifying SQL syntax, joins, or filters.
2. **Execution Timing Metric:** Latencies are measured using PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)` server-side **Execution Time** (in milliseconds). This excludes client parsing, query planning time, terminal formatting, and network round-trip overhead.
3. **Execution Repetitions & Sequence Order:** Every query was executed for **three consecutive runs** (`RUNS=3`). The raw plan files (`.txt`) capture the true chronological execution sequence: Run 1, Run 2, and Run 3.
4. **Write Isolation & Consistency:** Every WRITE query (`W01`–`W05`) was executed inside a `BEGIN; ... ROLLBACK;` transaction block. This ensured no state mutations persisted between runs, keeping the baseline table states strictly identical for all queries.
5. **Baseline Index Inventory:** The plans show primary-key and unique-index access, but do not prove that other secondary, partial, or expression indexes are absent. Before claiming the database contains no tuning indexes, verify the actual list using `SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = 'mmt' ORDER BY tablename, indexname;` and compare it with `sql/01_schema.sql`.
6. **Plan and Timing Reconciliation:** All 90 raw execution times across the 30 `.txt` files were extracted and reconciled against `benchmarks/results/baseline/summary.csv`. Every row matches to the thousandth of a millisecond (0.001 ms).

---

## 2. Complete Timing Results (All 30 Queries)

All timings are reported in **milliseconds (ms)**.  
The **Run 1**, **Run 2**, and **Run 3** columns report chronological execution order directly from each query's raw plan file (`=== <query_id> run <i> ===`). The **Min**, **Median**, **Max**, and **Average** columns match the metrics reported in `benchmarks/results/baseline/summary.csv`.

| SQL Query ID & Description | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Min (ms) | Median (ms) | Max (ms) | CSV Average (ms) |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **R01**: Flight search: Delhi → Mumbai, 5 July 2026, with seats left | READ | 7.784 | 7.211 | 6.157 | 6.157 | 7.211 | 7.784 | **7.051** |
| **R02**: Fare calendar: Bengaluru → Delhi, July 2026 | READ | 0.850 | 0.604 | 0.646 | 0.604 | 0.646 | 0.850 | **0.700** |
| **R03**: Hotel search: 4★+ Goa hotels with pool | READ | 1.415 | 0.243 | 0.240 | 0.240 | 0.243 | 1.415 | **0.633** |
| **R04**: Room availability: hotel 208, 10–12 July 2026 | READ | 5.076 | 2.295 | 2.309 | 2.295 | 2.309 | 5.076 | **3.227** |
| **R05**: My Trips: confirmed trips for customer 1021 | READ | 6.356 | 5.512 | 5.539 | 5.512 | 5.539 | 6.356 | **5.802** |
| **R06**: Support: booking lookup by reference | READ | 0.640 | 0.035 | 0.031 | 0.031 | 0.035 | 0.640 | **0.235** |
| **R07**: Airline manifest: passengers for flight 13047 | READ | 3.580 | 1.974 | 1.858 | 1.858 | 1.974 | 3.580 | **2.471** |
| **R08**: Low-load July flights (fewer than 5 booked passengers) | READ | 5.616 | 5.308 | 5.327 | 5.308 | 5.327 | 5.616 | **5.417** |
| **R09**: Top 10 most-booked routes, June 2026 | READ | 11.843 | 11.433 | 11.460 | 11.433 | 11.460 | 11.843 | **11.579** |
| **R10**: Flight status board: delayed flights | READ | 0.733 | 0.606 | 0.592 | 0.592 | 0.606 | 0.733 | **0.644** |
| **R11**: Bookings pending payment over 30 minutes | READ | 6.468 | 4.363 | 4.362 | 4.362 | 4.363 | 6.468 | **5.064** |
| **R12**: Monthly 2026 revenue by booking type | READ | 22.631 | 22.131 | 22.032 | 22.032 | 22.131 | 22.631 | **22.265** |
| **R13**: Coupons never used | READ | 11.452 | 11.234 | 11.058 | 11.058 | 11.234 | 11.452 | **11.248** |
| **R14**: Flight cancellation percentage by airline | READ | 28.470 | 33.696 | 75.373 | 28.470 | 33.696 | 75.373 | **45.846** |
| **R15**: Hotel room-nights by city, June 2026 | READ | 14.700 | 14.246 | 14.080 | 14.080 | 14.246 | 14.700 | **14.342** |
| **R16**: Booking-to-travel lead time by type and loyalty tier | READ | 63.463 | 57.191 | 55.814 | 55.814 | 57.191 | 63.463 | **58.823** |
| **R17**: Customers with 3+ completed trips (booked from 2026) | READ | 17.816 | 16.643 | 15.970 | 15.970 | 16.643 | 17.816 | **16.810** |
| **R18**: Goa reviews mentioning breakfast | READ | 5.035 | 4.229 | 4.183 | 4.183 | 4.229 | 5.035 | **4.482** |
| **R19**: Passenger counts for June 2026 flights | READ | 1174.750 | 1195.540 | 1225.159 | 1174.750 | 1195.540 | 1225.159 | **1198.483** |
| **R20**: Daily bookings and running total, June 2026 | READ | 6.843 | 6.525 | 6.509 | 6.509 | 6.525 | 6.843 | **6.626** |
| **R21**: Senior-citizen passengers (60+) by route | READ | 18.722 | 15.761 | 15.794 | 15.761 | 15.794 | 18.722 | **16.759** |
| **R22**: Booking list: page 4,001 (OFFSET 100000) | READ | 33.703 | 31.309 | 31.427 | 31.309 | 31.427 | 33.703 | **32.146** |
| **R23**: Case-insensitive customer email lookup | READ | 9.457 | 8.906 | 8.618 | 8.618 | 8.906 | 9.457 | **8.994** |
| **R24**: Goa hotels ranked by review ratings | READ | 1.624 | 1.660 | 1.618 | 1.618 | 1.624 | 1.660 | **1.634** |
| **R25**: Last-minute flight bookings in 2026 | READ | 19.011 | 17.402 | 16.959 | 16.959 | 17.402 | 19.011 | **17.791** |
| **W01**: Insert new pending flight booking | WRITE | 1.436 | 0.385 | 0.380 | 0.380 | 0.385 | 1.436 | **0.734** |
| **W02**: Confirm oldest pending-payment booking | WRITE | 13.475 | 9.823 | 9.636 | 9.636 | 9.823 | 13.475 | **10.978** |
| **W03**: Cancel booking MMA7772F with 70% refund | WRITE | 0.230 | 0.190 | 0.176 | 0.176 | 0.190 | 0.230 | **0.199** |
| **W04**: Mark past scheduled/delayed flights as departed | WRITE | 1.906 | 1.119 | 1.086 | 1.086 | 1.119 | 1.906 | **1.370** |
| **W05**: Assign room numbers for 1 July check-ins | WRITE | 4.247 | 2.631 | 2.492 | 2.492 | 2.631 | 4.247 | **3.123** |

---

### 2.1 Totals, Rounding Reconciliation, and Explanation

When aggregating execution latencies across 30 queries, two standard aggregation methods can be applied:

| Measurement Category | Run 1 Total (ms) | Run 2 Total (ms) | Run 3 Total (ms) | Method B: Mean of Run Totals (ms) | Method A: Sum of Rounded CSV Averages (ms) | Reconciled Delta (A − B) |
|---|---:|---:|---:|---:|---:|---:|
| **READ (25 queries)** | 1478.038 | 1476.057 | 1543.115 | **1499.070** | **1499.072** | +0.002 ms |
| **WRITE (5 queries)** | 21.294 | 14.148 | 13.770 | **16.404** | **16.404** | 0.000 ms |
| **Total Workload (30 queries)** | **1499.332** | **1490.205** | **1556.885** | **1515.474** | **1515.476** | **+0.002 ms** |

#### Why the 0.002 ms Difference Exists:
- **Method A (1515.476 ms):** Sums the 30 individual arithmetic averages displayed in `summary.csv`, each of which was rounded to three decimal places ($0.001\text{ ms}$) prior to summation.
- **Method B (1515.474 ms):** Sums the raw execution timings of each complete run ($\text{Run 1} = 1499.332\text{ ms}$, $\text{Run 2} = 1490.205\text{ ms}$, $\text{Run 3} = 1556.885\text{ ms}$) and computes their exact arithmetic mean:
  $$\frac{1499.332 + 1490.205 + 1556.885}{3} = \frac{4546.422}{3} = 1515.474\text{ ms}$$
Neither calculation is mathematically incorrect. The $0.002\text{ ms}$ difference is the expected consequence of accumulated intermediate rounding across 30 values. Both values are reported here for complete audit transparency.

---

### 2.2 Workload Distribution and Skew Analysis

- **READ vs. WRITE Query Time Comparison:**
  - **READ Average (25 queries):** Sum = $1499.072\text{ ms}$ (Method A) / $1499.070\text{ ms}$ (Method B).  
    Mean per query = $\mathbf{59.963\text{ ms}}$.
  - **WRITE Average (5 queries):** Sum = $16.404\text{ ms}$.  
    Mean per query = $\mathbf{3.281\text{ ms}}$.
- **Extreme Latency Skew Driven by R19:**
  - Query **R19** alone averages **1198.483 ms**, accounting for:
    - **79.08%** of the entire 30-query workload ($1198.483 / 1515.474$).
    - **79.95%** of the total READ execution time ($1198.483 / 1499.070$).
  - **The Remaining 24 READ Queries:**
    - Combined sum of averages: $1499.072 - 1198.483 = \mathbf{300.589\text{ ms}}$ (or $300.587\text{ ms}$ under Method B).
    - Mean per query: $\frac{300.589}{24} = \mathbf{12.525\text{ ms}}$.
  - Thus, 24 out of 25 READ queries execute in an average of just 12.5 ms. The baseline workload is overwhelmingly dominated by a single quadratic subquery pattern in R19.

---

## 3. Scan Types and Plan-Derived Analysis (All 30 Queries)

The table below reproduces the scan nodes recorded in the benchmark summary.  
*Formatting Note:* All internal separators are escaped (` \| `) so each scan description resides strictly within a single table cell.

> [!NOTE]
> The benchmark harness (`run_benchmark.sh`) captures scan nodes from the final execution run of each query. It removes the prefix `Parallel ` from `Parallel Seq Scan` nodes (e.g., in R11) and strips ` Backward`. Consult the raw `.txt` files for complete execution node trees.

| Query ID | Scan Nodes Reported by Script | Plan-Derived Execution Characteristics |
|---|---|---|
| **R01** | Seq Scan on flight_bookings \| Seq Scan on flights \| Index Scan using bookings_pkey on bookings | Filters flights by date and origin/destination (13,847 rows removed), then joins 84,899 flight_bookings via hash join and probes bookings by PK. |
| **R02** | Seq Scan on flights | Scans 13,848 flights to filter route and July departure dates, followed by grouped aggregation. Inexpensive at baseline size. |
| **R03** | Seq Scan on hotels | Scans 3,000 hotel rows evaluating JSONB amenities (`amenities ->> 'pool'`) and star rating. Average execution time is under 1 ms. |
| **R04** | Seq Scan on hotel_bookings \| Seq Scan on room_types \| Index Scan using bookings_pkey on bookings | Joins 59,893 hotel bookings with room types, checking bookings PK for status. Full scans process thousands of rows for a small availability check. |
| **R05** | Seq Scan on bookings \| Index Scan using flight_bookings_pkey on flight_bookings \| Index Scan using flights_pkey on flights \| Index Scan using hotel_bookings_id_hotel_uq on hotel_bookings | Scans all 144,792 bookings to find customer 1021; once filtered, uses primary-key indexes on flight_bookings and flights, plus a unique index (`hotel_bookings_id_hotel_uq`) on hotel_bookings. |
| **R06** | Index Scan using bookings_booking_ref_key on bookings | Point lookup on unique `booking_ref` uses an index scan; Run 2: 0.035 ms, with 4 shared-buffer hits. |
| **R07** | Seq Scan on flight_bookings \| Index Scan using bookings_pkey on bookings \| Index Scan using passengers_pk on passengers | Sequentially scans 84,899 flight bookings to match `flight_id = 13047`, then fetches booking and passenger records via primary key indexes. |
| **R08** | Seq Scan on flight_bookings \| Seq Scan on flights | Scans flights for July departures (13,848 rows) and joins all 84,899 flight bookings to compute passenger counts per flight. |
| **R09** | Seq Scan on flight_bookings \| Seq Scan on bookings \| Seq Scan on flights | Full scans on bookings, flight bookings, and flights to aggregate June route booking counts, followed by top-10 sorting. |
| **R10** | Seq Scan on flights | Filters 13,848 flights for `status = 'DELAYED'`. Quick sequential scan due to small table size. |
| **R11** | Seq Scan on bookings | Raw plan uses **Parallel Seq Scan** (1 worker planned & launched) filtering 144,792 bookings for `PENDING_PAYMENT` and age > 30 minutes, followed by Gather Merge. |
| **R12** | Seq Scan on bookings | Scans 144,792 bookings, filters for 2026 bookings, aggregates monthly revenue by type, and returns 12 grouped rows. |
| **R13** | Seq Scan on coupons \| Seq Scan on bookings | Scans 30 coupons and hashes 144,792 bookings for the `NOT IN` subquery. Returns 0 rows; this is consistent with the NULL-related `NOT IN` issue, but the plan alone does not establish the cause. Check `bookings.coupon_code IS NULL`. |
| **R14** | Seq Scan on bookings \| Seq Scan on flight_bookings \| Seq Scan on flights \| Seq Scan on airlines | Multi-table hash joins across airlines, flights, flight bookings, and bookings to calculate cancellation percentages; raw plan includes a **Parallel Seq Scan on bookings**. |
| **R15** | Seq Scan on bookings \| Seq Scan on hotel_bookings \| Seq Scan on hotels | Scans and joins hotel bookings with bookings and hotels to aggregate room-nights by city for June 2026. |
| **R16** | Seq Scan on bookings \| Seq Scan on customers \| Seq Scan on flight_bookings \| Seq Scan on flights \| Seq Scan on hotel_bookings | Multi-table hash left joins across bookings, customers, flight bookings, flights, and hotel bookings to calculate lead time by tier; raw plan includes a **Parallel Seq Scan on bookings**. |
| **R17** | Seq Scan on bookings | Scans 144,792 bookings for completed trips in 2026, groups by customer, filters `HAVING count(*) >= 3`, and sorts. |
| **R18** | Seq Scan on hotel_reviews \| Seq Scan on hotels | Scans 15,913 hotel reviews for `%breakfast%` substring (ILIKE) and joins Goa hotels, sorting by `r.created_at DESC`. |
| **R19** | Seq Scan on flights \| Seq Scan on flight_bookings \| Index Only Scan using passengers_pk on passengers | Scans 720 June flights and executes a correlated subquery **720 times**. Each loop sequentially scans 84,899 flight bookings and probes passengers PK. |
| **R20** | Seq Scan on bookings | Raw plan uses a **Parallel Seq Scan on bookings** for June 2026, then groups by day and computes the cumulative running total using a window function. |
| **R21** | Seq Scan on passengers \| Seq Scan on flight_bookings \| Seq Scan on flights | Full scans of passengers (163,380 rows), flight bookings, and flights to count senior citizen travelers by route. |
| **R22** | Seq Scan on bookings | Scans 144,792 bookings and sorts by `booked_at DESC`. Spills to disk via external merge sort to evaluate `OFFSET 100000 LIMIT 25`. |
| **R23** | Seq Scan on customers | Scans all 40,000 customer rows evaluating `lower(email) = 'siddharth.sharma1021@rediffmail.com'`. Lacks functional index. |
| **R24** | Seq Scan on hotel_reviews \| Seq Scan on hotels | Scans reviews and hotels for Goa properties, groups by hotel to compute average review ratings, and sorts and returns the top 20. |
| **R25** | Seq Scan on flight_bookings \| Seq Scan on bookings \| Seq Scan on flights | Joins bookings, flight bookings, and flights to identify last-minute bookings (< 24h lead time) in 2026. |
| **W01** | (no scan) | Single-row `INSERT` into `bookings`. Time spent in constraint checking and PK index maintenance. |
| **W02** | Index Scan using bookings_pkey on bookings | Scans `bookings_pkey` in order of `booking_id` filtering for `status = 'PENDING_PAYMENT'`, rejecting 144,695 rows before finding the target row. |
| **W03** | Index Scan using bookings_booking_ref_key on bookings | Direct index point lookup on unique `booking_ref` followed by single-row update and rollback. Highly efficient (~0.2 ms). |
| **W04** | Seq Scan on flights | Scans 13,848 flights to locate scheduled/delayed flights departing before 1 July 2026 and updates status to `DEPARTED`. |
| **W05** | Seq Scan on hotel_bookings \| Index Scan using bookings_pkey on bookings | Scans 59,893 hotel bookings for check-in date 2026-07-01 and NULL room number, validating booking status via PK lookup. |

---

## 4. In-Depth Plan Verification & Phase 4 Optimization Hypotheses

All analysis below is verified directly against the 30 raw execution plans in `benchmarks/results/baseline/`.

### 4.1 Priority 1 Bottleneck: R19 — 1198.483 ms (79.08% of Workload)

#### Physical Execution Plan Evidence:
- **Correlated Subquery Loops:** The outer scan on `mmt.flights` identifies **720** flights departing in June 2026.
- **Inner Plan Repetitions:** For every single outer flight row, `SubPlan 1` is invoked (**720 loops**).
- **Nested Loop & Table Scan:** Inside each loop, `Seq Scan on flight_bookings fb` scans all 84,899 rows, discarding **84,892** rows per loop ($720 \times 84,892 \approx 61.1\text{ million}$ rejected row checks). It then executes an `Index Only Scan using passengers_pk on passengers` ($4,781$ index lookups).
- **Buffer Thrashing:** Run 1 reports **463,725 shared-buffer hits and 64 disk reads**. Runs 2 and 3 report **463,789 shared-buffer hits**.
- **Optimization Hypothesis for Phase 4:**
  1. **Query Rewrite:** Eliminate the correlated scalar subquery. Replace it with an explicit `LEFT JOIN` to a pre-aggregated subquery or CTE grouped by `flight_id`, or use an outer join with `GROUP BY f.flight_id`.
  2. **Supporting Index:** Add a composite covering index on `flight_bookings(flight_id, booking_id)`.
- **Potential Benefit:** Replacing 720 repetitive scans with pre-aggregation or more selective indexed access may substantially reduce execution time; the actual speedup must be measured in Phase 4.
- **Verification Method:** Compare `EXPLAIN (ANALYZE, BUFFERS)` on the rewritten query under identical data, checking execution time, loops, buffer hits and output equivalence.

---

### 4.2 Priority 2 Bottleneck: R16 — 58.823 ms

#### Physical Execution Plan Evidence:
- **Multi-Table Hash Outer Joins:** Joins `bookings` (144,792 rows), `customers` (40,000 rows), `flight_bookings` (84,899 rows), `flights` (13,848 rows), and `hotel_bookings` (59,893 rows).
- **Memory Consumption:** Builds an in-memory hash table of 4,341 kB on `flight_bookings` and 2,251 kB on `customers`. It performs 144,000+ join evaluations to group records into just 8 final result rows.
- **Optimization Hypothesis for Phase 4:**
  1. Do not duplicate indexes on `flight_bookings(booking_id)` or `hotel_bookings(booking_id)`: both are already indexed by primary-key constraints. Evaluate other selective predicates or join paths using measured plans.
  2. Filter unnecessary rows prior to joining or evaluate join pruning.
- **Expected Benefit:** Reduce join memory overhead and CPU aggregation cycles.
- **Verification Method:** Verify plan memory usage and execution time reduction via benchmark runs.

---

### 4.3 Priority 3 Bottleneck: R14 — 45.846 ms & Large Run Variance

#### Physical Execution Plan Evidence:
- **Large Join & Group Aggregate:** Evaluates cancellation rates across airlines by joining `airlines`, `flights`, `flight_bookings`, and `bookings`.
- **Timing Instability:** Marked run variation:
  - Run 1: **28.470 ms**
  - Run 2: **33.696 ms**
  - Run 3: **75.373 ms** (Confirmed from raw plan as the slowest run).
- **Observed Variance:** The plan uses parallel processing, but the three runs do not establish why Run 3 took longer. Worker scheduling, I/O or other system activity are possibilities, not verified causes.
- **Optimization Hypothesis for Phase 4:**
  1. Add index coverage on `flights(airline_code, flight_id)` and `flight_bookings(flight_id, booking_id)`.
  2. Test pre-aggregating cancellation counts per flight before joining to airlines.
- **Potential Benefit:** May reduce aggregation and join cost; measure the average and variation after optimization before claiming an improvement.
- **Verification Method:** Measure multi-run variance across 5+ runs to confirm stability.

---

### 4.4 Priority 4 Bottleneck: R22 — 32.146 ms & Sort Spill to Disk

#### Physical Execution Plan Evidence:
- **Deep Pagination Cost (`OFFSET 100000 LIMIT 25`):** To return 25 rows on page 4,001, PostgreSQL sequentially scans all **144,792** rows of `mmt.bookings`.
- **Disk Spill:** The raw plan confirms `Sort Method: external merge Disk: 8224kB`; the sort spilled to temporary disk. The actual `work_mem` setting has not been independently checked (run `SHOW work_mem;`). The sort node processes **100,025 rows**, discarding 100,000 rows.
- **Optimization Hypothesis for Phase 4:**
  1. **Keyset Pagination (alternative application behavior, not an equivalent drop-in replacement for page 4,001):** For sequential next-page navigation with a known cursor, a possible query is:
     ```sql
     WHERE (booked_at, booking_id) < ($last_booked_at, $last_booking_id)
     ORDER BY booked_at DESC, booking_id DESC LIMIT 25;
     ```
  2. **Index Support:** Test a B-tree index on `bookings(booked_at DESC)` for the unchanged OFFSET query; a `(booked_at DESC, booking_id DESC)` index is relevant to the alternative cursor query.
- **Potential Benefit:** An appropriate index may avoid the disk sort; test the actual plan and timing. Keyset pagination cannot jump directly to page 4,001 without a prior cursor, and adding `booking_id` as a tie-breaker can change which rows appear when timestamps tie.
- **Verification Method:** Compare the original query's output and `EXPLAIN (ANALYZE, BUFFERS)` after indexing. Consider cursor pagination separately only if application requirements permit changed paging semantics.

---

### 4.5 Priority 5 Bottleneck: W02 — 10.978 ms (Slowest WRITE Query)

#### Physical Execution Plan Evidence:
- **Subquery Filter Inefficiency:** `W02` updates the pending-payment booking with the **smallest `booking_id`**, which is not necessarily the earliest `booked_at`:
  ```sql
  WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT');
  ```
- **Filter Elimination:** PostgreSQL optimizes the `min(booking_id)` subquery with a `Limit` and an `Index Scan using bookings_pkey on bookings` reading in `booking_id` order. Because pending-payment bookings are sparse, it evaluates rows one by one, recording **`Rows Removed by Filter: 144695`** before finding the first matching row.
- **Optimization Hypothesis for Phase 4:**
  - Create a partial index:
    ```sql
    CREATE INDEX idx_bookings_pending_payment ON bookings(booking_id) WHERE status = 'PENDING_PAYMENT';
    ```
- **Potential Benefit:** The partial index may avoid filtering 144,695 unrelated rows; measure the resulting access path and execution time.
- **Verification Method:** Check whether the partial index is chosen and whether rows removed by filter and execution time decrease.

---

### 4.6 Priority 6 Bottleneck: R23 — 8.994 ms (Case-Insensitive Lookup Using Seq Scan)

#### Physical Execution Plan Evidence:
- Scans all **40,000** customer rows via `Seq Scan on customers` evaluating `Filter: (lower((email)::text) = 'siddharth.sharma1021@rediffmail.com'::text)`.
- Even though only 1 row matches, the observed plan uses a full-table sequential scan. The plan does not establish whether an expression index on `lower(email)` is absent or was simply not chosen; verify with `pg_indexes`.
- **Optimization Hypothesis for Phase 4:**
  - Add an expression index:
    ```sql
    CREATE INDEX idx_customers_lower_email ON customers(lower(email));
    ```
- **Potential Benefit:** An index on `lower(email)` may replace the 40,000-row sequential scan with selective index access; confirm the improvement by benchmarking.
- **Verification Method:** Confirm `Index Scan using idx_customers_lower_email` in EXPLAIN plan.

---

### 4.7 Baseline SQL Correctness & Semantic Observations

1. **R13 (`NOT IN` Subquery with NULL Values):**
   - **Baseline SQL:**
     ```sql
     SELECT c.coupon_code, c.applies_to, c.discount_pct
     FROM coupons c
     WHERE c.coupon_code NOT IN (SELECT b.coupon_code FROM bookings b);
     ```
   - **Plan Observation:** The plan executes a `Seq Scan on coupons c` with `Filter: (NOT (ANY ((coupon_code)::text = ((hashed SubPlan 1).col1)::text)))` and reports **`rows=0.00` (zero rows returned)**.
   - **Semantic Bug Analysis:** In SQL three-valued logic, if `bookings.coupon_code` contains a `NULL`, `c.coupon_code NOT IN (SELECT ...)` evaluates to `UNKNOWN` for any coupon code not found among the non-NULL values. This can explain the observed zero-row result, but the execution plan does not prove a NULL exists. Confirm with `SELECT count(*) FROM mmt.bookings WHERE coupon_code IS NULL;` and compare the original query with the `NOT EXISTS` rewrite.
   - **Phase 4 Correction (after confirming the NULL issue):** Maintain the exact query for Phase 3 baseline compliance. In Phase 4, test this `NOT EXISTS` rewrite:
     ```sql
     SELECT c.coupon_code, c.applies_to, c.discount_pct
     FROM coupons c
     WHERE NOT EXISTS (SELECT 1 FROM bookings b WHERE b.coupon_code = c.coupon_code);
     ```
2. **R05 Description vs. Implementation:**
   - The workload comment describes *"customer 1021's upcoming confirmed trips"*, but the SQL contains `WHERE b.customer_id = 1021 AND b.status = 'CONFIRMED'` without filtering on `travel_date >= CURRENT_DATE`.
3. **R17 Description vs. Implementation:**
   - The workload comment describes *"trips that started in 2026"*, but the SQL filters on `b.booked_at >= '2026-01-01'` rather than flight departure or hotel check-in dates.

---

## 5. Baseline Reproducibility Guide (From Scratch)

To recreate the baseline database, schema, data, and benchmark timings from an empty PostgreSQL cluster, execute the following steps from the repository root:

```bash
# 1. Ensure PostgreSQL client utilities are in PATH
export PATH="/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH"

# 2. Recreate fresh baseline database (OPTIONAL: destructive; back up data first)
# WARNING: dropdb permanently deletes the existing mmt_baseline database.
dropdb --if-exists mmt_baseline
createdb mmt_baseline

# 3. Create schema and integrity constraints (clean baseline, no tuning indexes)
# Note: verify the actual sql/01_schema.sql in your repository, including the email regex. This file was not part of the uploaded benchmark ZIP.
psql -d mmt_baseline -f sql/01_schema.sql

# 4. Ingest seed dataset and execute table validation checks
psql -d mmt_baseline -f sql/02_load_data.sql

# 5. Confirm primary table counts match expected figures
psql -d mmt_baseline -c "
SELECT 'bookings' AS tbl, count(*) FROM mmt.bookings
UNION ALL SELECT 'customers', count(*) FROM mmt.customers
UNION ALL SELECT 'flights', count(*) FROM mmt.flights
UNION ALL SELECT 'flight_bookings', count(*) FROM mmt.flight_bookings;"

# 6. Execute the official 30-query benchmark harness (3 runs per query)
./benchmarks/run_benchmark.sh mmt_baseline baseline 3

# 7. Verify generated artifacts
ls -la benchmarks/results/baseline/summary.csv
ls -la benchmarks/results/baseline/*.txt | wc -l # Must return 30 files
```

### Verified File Structure for Submission:
```text
docs/03_baseline_timings.md
benchmarks/results/baseline/summary.csv
benchmarks/results/baseline/R01.txt ... R25.txt
benchmarks/results/baseline/W01.txt ... W05.txt
```

---

## 6. Baseline Conclusion and Phase 4 Roadmap

### 6.1 Baseline Performance Profile Summary
The Phase 3 baseline evaluation establishes an unaltered performance benchmark for the MakeMyTrip workload on PostgreSQL:
- **Total Workload Execution Time:** **1515.474 ms** (mean of runs) / **1515.476 ms** (sum of rounded averages).
- **READ Dominance:** READ queries account for **1499.070 ms** ($98.92\%$) of total execution time.
- **WRITE Efficiency:** Total WRITE time (sum of the five per-query averages): **16.404 ms** ($1.08\%$ of total workload time); **mean per WRITE query: 3.281 ms**. The actual index inventory must be verified before attributing the timings to the absence of secondary indexes.
- **Bottleneck Hierarchy:**
  1. **R19 (Correlated Subquery):** Consumes **79.08%** of the entire workload ($1198.483\text{ ms}$).
  2. **R16 & R14 (Unindexed Large Hash Joins):** Account for $58.823\text{ ms}$ and $45.846\text{ ms}$ respectively.
  3. **R22 (Deep Pagination & Disk Spill):** Consumes $32.146\text{ ms}$ and spills $8,224\text{ kB}$ to temporary disk files.
  4. **W02 & R23 (Unindexed Filtering):** Account for $10.978\text{ ms}$ and $8.994\text{ ms}$ due to full-table predicate evaluations.

### 6.2 Actionable Roadmap for Phase 4 Optimization
In Phase 4, the database will be optimized systematically without altering data integrity or baseline query requirements:
1. **Query Architecture Rewrites:**
   - Rewrite **R19** to replace the correlated scalar subquery with a pre-aggregated join or CTE.
   - Verify the **R13** `NOT IN` / NULL behavior and, if confirmed, use `NOT EXISTS` in Phase 4 to correct it.
   - Test an index for the original **R22** OFFSET query; consider keyset pagination only if alternative paging semantics are allowed.
2. **Targeted Secondary Index Design:**
   - **Composite Covering Indexes:** Index `flight_bookings(flight_id, booking_id)` to accelerate R19 and R07.
   - **Partial Indexes:** Create `idx_bookings_pending_payment` on `bookings(booking_id) WHERE status = 'PENDING_PAYMENT'` to eliminate 144,695 row checks in W02 and accelerate R11.
   - **Functional / Expression Indexes:** Create `idx_customers_lower_email` on `customers(lower(email))` to eliminate sequential table scans in R23.
   - **Foreign Key Indexing:** Test indexes on relevant referencing columns such as `bookings.customer_id`, `flight_bookings.flight_id`, and `hotel_bookings.hotel_id`; confirm no equivalent indexes already exist and benchmark their effect on R09, R14, R15, and R16.
3. **Verification Criteria:**
   - Benchmark Phase 4 under identical hardware, PostgreSQL configuration, and dataset.
   - Compare before vs. after execution times, buffer hits, and physical scan node types in `docs/04_optimization_report.md`.
