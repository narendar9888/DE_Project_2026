-- =====================================================================
-- MakeMyTrip DBMS Project — Phase 4 Indexing & Materialized View Strategy
-- Database: PostgreSQL 15+ (schema: mmt)
--
-- Design goals:
--   1. Eliminate full sequential scans on high-frequency OLTP & partner queries.
--   2. Use covering indexes (INCLUDE) for Index Only Scans on hot paths.
--   3. Use partial indexes for sparse statuses/predicates to keep index size
--      and write overhead (W01–W05) minimal.
--   4. Consolidate date-ranged analytics on bookings into a single multi-purpose
--      covering index instead of creating redundant overlapping indexes.
--   5. Use concurrently-refreshable Materialized Views for lifetime executive
--      reports (R14, R16) that do not require live millisecond freshness.
-- =====================================================================

SET search_path TO mmt;

-- Required for GIN trigram index on hotel_reviews.review_text (R18)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------
-- 1. FLIGHTS
-- ---------------------------------------------------------------------

-- Serves: R01 (flight search), R02 (fare calendar)
-- Type: Composite covering B-tree
-- Column order: Equality columns (origin, destination) first, then range/sort
-- column (departure_at). INCLUDE columns allow R02 to run as an Index Only Scan
-- and avoid heap lookups during R01 route/date filtering.
CREATE INDEX idx_flights_route_dep
    ON flights (origin, destination, departure_at)
    INCLUDE (base_fare, flight_no, arrival_at, total_seats, status);

-- Serves: R08 (low-load scheduled flights), R10 (delayed flights), W04 (departed batch update)
-- Type: Partial covering B-tree
-- Why: Only ~5.4% of flights are SCHEDULED or DELAYED (754 of 13,848 rows).
-- Ordering by (status, departure_at) satisfies equality on status and range/ORDER BY
-- on departure_at with zero sorting and tiny index footprint.
CREATE INDEX idx_flights_active_dep
    ON flights (status, departure_at)
    INCLUDE (flight_id, flight_no, origin, destination)
    WHERE status IN ('SCHEDULED', 'DELAYED');

-- Serves: R19 (June 2026 flight passenger counts), R21 (2026 senior passengers), R25 (2026 last-minute flights)
-- Type: Composite covering B-tree
-- Column order: Range column (departure_at) leading to prune historical 2025 flights,
-- with flight_id and route/flight metadata included for Index Only Scans.
CREATE INDEX idx_flights_departure_at
    ON flights (departure_at, flight_id)
    INCLUDE (flight_no, origin, destination);

-- ---------------------------------------------------------------------
-- 2. FLIGHT_BOOKINGS & PASSENGERS
-- ---------------------------------------------------------------------

-- Serves: R01, R07 (manifest), R08, R19 (June passenger counts), R21
-- Type: Composite covering B-tree on foreign key flight_id
-- Column order: flight_id (equality/join key) first, booking_id second to join
-- cleanly into bookings_pkey and passengers_pk. INCLUDE (passengers) eliminates
-- heap fetches for R01 and R08.
CREATE INDEX idx_flight_bookings_flight_id
    ON flight_bookings (flight_id, booking_id)
    INCLUDE (passengers);

-- Serves: R09 (top June routes), R25 (last-minute 2026 flight bookings)
-- Type: Covering B-tree on booking_id
-- Why: Enables Index Only Scans from booking_id -> (flight_id, passengers)
-- without scanning all 84,899 rows of flight_bookings when joining a narrow
-- date-filtered subset of bookings.
CREATE INDEX idx_flight_bookings_booking_flight
    ON flight_bookings (booking_id)
    INCLUDE (flight_id, passengers);

-- Serves: R21 (senior-citizen passengers 60+ per route in 2026)
-- Type: Partial B-tree
-- Why: Only ~22.5% of passengers are age >= 60 (36,837 of 163,380 rows).
-- Indexing only qualifying booking_ids enables an Index Only Scan without scanning
-- the full 163k-row passengers table.
CREATE INDEX idx_passengers_senior_booking
    ON passengers (booking_id)
    WHERE age >= 60;

-- ---------------------------------------------------------------------
-- 3. HOTELS, ROOM_TYPES, HOTEL_BOOKINGS & HOTEL_REVIEWS
-- ---------------------------------------------------------------------

-- Serves: R03 (4★+ Goa hotels with swimming pool, best rated first)
-- Type: Partial covering B-tree
-- Column order: city_name (equality) first, user_rating DESC NULLS LAST second
-- to match ORDER BY and stop after LIMIT 20 without sorting. Partial predicate
-- restricts index to pool-equipped hotels.
CREATE INDEX idx_hotels_city_pool_rating
    ON hotels (city_name, user_rating DESC NULLS LAST)
    INCLUDE (hotel_id, hotel_name, star_rating)
    WHERE (amenities ->> 'pool') = 'true';

-- Serves: R15 (room-nights by city), R18 (Goa breakfast reviews), R24 (Goa hotel ranking)
-- Type: Composite covering B-tree
-- Column order: city_name (equality) first, hotel_id second for fast city-scoped joins.
CREATE INDEX idx_hotels_city_id
    ON hotels (city_name, hotel_id)
    INCLUDE (hotel_name);

-- Serves: R04 (room availability for hotel 208)
-- Type: Composite covering B-tree on foreign key hotel_id
-- Column order: hotel_id (equality) first, price_per_night second to match ORDER BY
-- with an Index Only Scan.
CREATE INDEX idx_room_types_hotel_id
    ON room_types (hotel_id, price_per_night)
    INCLUDE (room_type_id, room_name, total_rooms);

-- Serves: R04 (room availability overlap check for specific room_type_id)
-- Type: Composite covering B-tree
-- Column order: room_type_id (equality/join key) first, followed by date bounds
-- (check_in, check_out) with INCLUDE (booking_id, rooms) for Index Only Scan.
CREATE INDEX idx_hotel_bookings_room_dates
    ON hotel_bookings (room_type_id, check_in, check_out)
    INCLUDE (booking_id, rooms);

-- Serves: R15 (room-nights sold per city in June 2026)
-- Type: Composite covering B-tree
-- Column order: check_out leading because check_out > '2026-06-01' prunes >90%
-- of historical stays (whereas check_in < '2026-07-01' matches almost the entire table).
CREATE INDEX idx_hotel_bookings_checkout_checkin
    ON hotel_bookings (check_out, check_in)
    INCLUDE (booking_id, hotel_id, rooms);

-- Serves: W05 (assign room numbers for 1 July check-ins where room_number IS NULL)
-- Type: Partial B-tree
-- Why: Almost all historical hotel bookings already have room numbers assigned.
-- Indexing only room_number IS NULL rows keeps this index tiny and accelerates W05
-- without adding maintenance cost to already-assigned bookings.
CREATE INDEX idx_hotel_bookings_unassigned_checkin
    ON hotel_bookings (check_in, booking_id)
    WHERE room_number IS NULL;

-- Serves: R24 (Goa hotels ranked by review rating), R18 (Goa breakfast reviews)
-- Type: Composite covering B-tree on foreign key hotel_id
-- Column order: hotel_id (join key) first, created_at DESC second to support
-- newest-first ordering in R18 and Index Only aggregation in R24.
CREATE INDEX idx_hotel_reviews_hotel_created
    ON hotel_reviews (hotel_id, created_at DESC)
    INCLUDE (rating, review_id);

-- Serves: R18 (Goa reviews mentioning 'breakfast' via ILIKE '%breakfast%')
-- Type: GIN trigram index (pg_trgm)
-- Why: Standard B-tree indexes cannot accelerate leading-wildcard ILIKE '%text%'.
-- A GIN trigram index locates matching review rows directly via bitmap index scan.
CREATE INDEX idx_hotel_reviews_text_trgm
    ON hotel_reviews USING gin (review_text gin_trgm_ops);

-- ---------------------------------------------------------------------
-- 4. BOOKINGS (Carefully budgeted to control W01–W03 write overhead)
-- ---------------------------------------------------------------------

-- Serves: R09, R12, R17, R20, R22 (keyset pagination), R25
-- Type: Multi-purpose composite covering B-tree
-- Column order: (booked_at DESC, booking_id DESC) directly matches R22 keyset
-- pagination and prunes date ranges for R09, R12, R17, R20, R25. INCLUDE columns
-- enable Index Only Scans for 6 different queries using just ONE general index.
CREATE INDEX idx_bookings_booked_at_id
    ON bookings (booked_at DESC, booking_id DESC)
    INCLUDE (booking_type, status, total_amount, customer_id, booking_ref);

-- Serves: R05 ("My Trips": customer confirmed trips)
-- Type: Partial covering B-tree
-- Why: CONFIRMED bookings are only ~3.3% of the table (4,806 of 144,792 rows).
-- Partial indexing keeps size tiny and adds zero overhead to PENDING_PAYMENT inserts (W01).
CREATE INDEX idx_bookings_customer_confirmed
    ON bookings (customer_id)
    INCLUDE (booking_id, booking_ref, booking_type, total_amount)
    WHERE status = 'CONFIRMED';

-- Serves: R11 (payments: pending bookings older than 30 minutes)
-- Type: Partial covering B-tree
-- Why: PENDING_PAYMENT represents <0.1% of bookings (97 rows). Ordering by
-- booked_at satisfies both range filter and ORDER BY with an Index Only Scan.
CREATE INDEX idx_bookings_pending_booked_at
    ON bookings (booked_at)
    INCLUDE (booking_id, booking_ref, customer_id, total_amount)
    WHERE status = 'PENDING_PAYMENT';

-- Serves: W02 (confirm oldest pending-payment booking via min(booking_id))
-- Type: Partial B-tree
-- Why: Allows PostgreSQL to resolve min(booking_id) WHERE status = 'PENDING_PAYMENT'
-- from the very first leaf entry instead of scanning 144,695 rows via bookings_pkey.
CREATE INDEX idx_bookings_pending_id
    ON bookings (booking_id)
    WHERE status = 'PENDING_PAYMENT';

-- Serves: R13 (marketing: coupons never used via NOT EXISTS)
-- Type: Partial B-tree
-- Why: Only 12.2% of bookings use a coupon (17,648 of 144,792 rows). Partial
-- indexing excludes NULLs, keeps size minimal, and avoids write overhead on non-coupon inserts (W01).
CREATE INDEX idx_bookings_coupon_code
    ON bookings (coupon_code)
    WHERE coupon_code IS NOT NULL;

-- Serves: R15 (hotel room-nights in June 2026 excluding cancelled bookings)
-- Type: Partial B-tree on booking_id
-- Why: Lets R15 verify b.status <> 'CANCELLED' for the ~3,375 June hotel bookings
-- via an Index Only Scan instead of sequentially scanning all 144,792 bookings.
-- Adds zero overhead to FLIGHT inserts (W01).
CREATE INDEX idx_bookings_hotel_active
    ON bookings (booking_id)
    WHERE booking_type = 'HOTEL' AND status <> 'CANCELLED';

-- ---------------------------------------------------------------------
-- 5. CUSTOMERS
-- ---------------------------------------------------------------------

-- Serves: R23 (case-insensitive email sign-in lookup)
-- Type: Expression covering B-tree
-- Why: Indexes the exact lower(email) expression used in WHERE, with INCLUDE
-- columns enabling a single-row Index Only Scan.
CREATE INDEX idx_customers_lower_email
    ON customers (lower(email))
    INCLUDE (customer_id, full_name, loyalty_tier);

-- ---------------------------------------------------------------------
-- 6. MATERIALIZED VIEWS (Lifetime Analytics / Partner Reports)
-- ---------------------------------------------------------------------
-- Refresh policy: Scheduled off-peak refresh (hourly or nightly via pg_cron) using
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mmt.mv_airline_cancel_rates;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mmt.mv_booking_lead_time;
-- Unique indexes enable non-blocking concurrent refreshes.

-- Serves: R14 (Airline partnerships: lifetime cancellation rate per airline)
CREATE MATERIALIZED VIEW mv_airline_cancel_rates AS
SELECT a.airline_name,
       count(*) AS bookings,
       round(100.0 * count(*) FILTER (WHERE b.status = 'CANCELLED') / count(*), 2) AS cancel_pct
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
JOIN airlines a         ON a.airline_code = f.airline_code
WHERE b.booking_type = 'FLIGHT'
GROUP BY a.airline_name;

CREATE UNIQUE INDEX idx_mv_airline_cancel_rates_pk
    ON mv_airline_cancel_rates (airline_name);

-- Serves: R16 (Insights: average booking-to-travel lead days by booking type & loyalty tier)
CREATE MATERIALIZED VIEW mv_booking_lead_time AS
SELECT 'FLIGHT'::varchar(10) AS booking_type,
       c.loyalty_tier,
       round(avg(f.departure_at::date - b.booked_at::date), 1) AS avg_lead_days
FROM bookings b
JOIN customers c        ON c.customer_id = b.customer_id
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE b.booking_type = 'FLIGHT'
GROUP BY c.loyalty_tier

UNION ALL

SELECT 'HOTEL'::varchar(10) AS booking_type,
       c.loyalty_tier,
       round(avg(hb.check_in - b.booked_at::date), 1) AS avg_lead_days
FROM bookings b
JOIN customers c       ON c.customer_id = b.customer_id
JOIN hotel_bookings hb ON hb.booking_id = b.booking_id
WHERE b.booking_type = 'HOTEL'
GROUP BY c.loyalty_tier;

CREATE UNIQUE INDEX idx_mv_booking_lead_time_pk
    ON mv_booking_lead_time (booking_type, loyalty_tier);

-- ---------------------------------------------------------------------
-- 7. MAINTENANCE: Refresh planner statistics & visibility maps
-- ---------------------------------------------------------------------
-- Setting visibility map bits enables PostgreSQL Index Only Scans without heap fetches.
VACUUM ANALYZE;
