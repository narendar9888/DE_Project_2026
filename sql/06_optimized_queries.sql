-- =====================================================================
-- MakeMyTrip DBMS Project — Phase 4 Optimized Workload (30 Queries)
--   R01–R25 : read queries  (25)
--   W01–W05 : write queries (5)
--
-- Rewritten queries (all others unchanged, served by sql/05_indexes.sql):
--   * R01 : Sargable departure_at timestamp range (replaces DATE(f.departure_at))
--   * R02 : Sargable departure_at timestamp range (replaces departure_at::date BETWEEN)
--   * R09 : Explicit b.booking_type = 'FLIGHT' predicate to match covering indexes
--   * R12 : Sargable booked_at timestamp range (replaces EXTRACT(YEAR FROM booked_at))
--   * R13 : NOT EXISTS rewrite fixing the NULL-absorption bug in NOT IN
--   * R14 : Reads pre-aggregated materialized view mv_airline_cancel_rates
--   * R15 : Explicit b.booking_type = 'HOTEL' predicate matching partial index idx_bookings_hotel_active
--   * R16 : Reads pre-aggregated materialized view mv_booking_lead_time
--   * R19 : LEFT JOIN + GROUP BY replacing the 720-loop correlated subquery
--   * R20 : Sargable booked_at timestamp range (replaces booked_at::date BETWEEN)
--   * R22 : Keyset pagination replacing OFFSET 100000 disk sort
--   * R25 : Explicit b.booking_type = 'FLIGHT' and f.departure_at >= '2026-01-01' range pruning
-- =====================================================================
SET search_path TO mmt;
BEGIN;

-- @R01
-- Flight search: Delhi → Mumbai on 5 July 2026 with seats left
-- REWRITTEN: Sargable timestamp range replaces DATE(f.departure_at) = '2026-07-05'
SELECT f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare,
       f.total_seats - coalesce(sum(fb.passengers) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS seats_left
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN bookings b         ON b.booking_id = fb.booking_id
WHERE f.origin = 'DEL' AND f.destination = 'BOM'
  AND f.departure_at >= TIMESTAMPTZ '2026-07-05 00:00:00+05:30'
  AND f.departure_at <  TIMESTAMPTZ '2026-07-06 00:00:00+05:30'
  AND f.status <> 'CANCELLED'
GROUP BY f.flight_id, f.flight_no, f.departure_at, f.arrival_at, f.base_fare, f.total_seats
ORDER BY f.departure_at;

-- @R02
-- Fare calendar: cheapest Bengaluru → Delhi fare for each day of July 2026
-- REWRITTEN: Sargable timestamp range replaces departure_at::date BETWEEN
SELECT departure_at::date AS day, min(base_fare) AS cheapest_fare
FROM flights
WHERE origin = 'BLR' AND destination = 'DEL'
  AND departure_at >= TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
  AND departure_at <  TIMESTAMPTZ '2026-08-01 00:00:00+05:30'
GROUP BY 1
ORDER BY 1;

-- @R03
-- Hotel search: 4★+ hotels in Goa with a swimming pool, best rated first
SELECT hotel_id, hotel_name, star_rating, user_rating
FROM hotels
WHERE city_name = 'Goa'
  AND star_rating >= 4
  AND amenities ->> 'pool' = 'true'
ORDER BY user_rating DESC NULLS LAST
LIMIT 20;

-- @R04
-- Room availability: rooms left per room type of hotel 208 for 10–12 July 2026
SELECT rt.room_type_id, rt.room_name, rt.price_per_night,
       rt.total_rooms - coalesce(sum(hb.rooms) FILTER (WHERE b.status <> 'CANCELLED'), 0) AS rooms_left
FROM room_types rt
LEFT JOIN hotel_bookings hb ON hb.room_type_id = rt.room_type_id
                           AND hb.check_in < '2026-07-12' AND hb.check_out > '2026-07-10'
LEFT JOIN bookings b        ON b.booking_id = hb.booking_id
WHERE rt.hotel_id = 208
GROUP BY rt.room_type_id, rt.room_name, rt.price_per_night, rt.total_rooms
ORDER BY rt.price_per_night;

-- @R05
-- "My Trips": customer 1021's upcoming confirmed trips
SELECT b.booking_ref, b.booking_type, b.total_amount,
       coalesce(f.departure_at::date, hb.check_in) AS travel_date
FROM bookings b
LEFT JOIN flight_bookings fb ON fb.booking_id = b.booking_id
LEFT JOIN flights f          ON f.flight_id = fb.flight_id
LEFT JOIN hotel_bookings hb  ON hb.booking_id = b.booking_id
WHERE b.customer_id = 1021 AND b.status = 'CONFIRMED'
ORDER BY travel_date;

-- @R06
-- Support: open a booking by its reference
SELECT booking_id, customer_id, booking_type, status, total_amount, booked_at
FROM bookings
WHERE booking_ref = 'MMA7772F';

-- @R07
-- Airline manifest: passengers on flight 13047 ordered by seat
SELECT p.full_name, p.age, p.gender, p.seat_no, b.booking_ref
FROM flight_bookings fb
JOIN bookings b   ON b.booking_id = fb.booking_id AND b.status <> 'CANCELLED'
JOIN passengers p ON p.booking_id = fb.booking_id
WHERE fb.flight_id = 13047
ORDER BY p.seat_no NULLS LAST, p.full_name;

-- @R08
-- Revenue management: July 2026 flights with fewer than 5 passengers booked
SELECT f.flight_id, f.flight_no, f.departure_at, coalesce(sum(fb.passengers), 0) AS passengers
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
WHERE f.departure_at >= '2026-07-01' AND f.status = 'SCHEDULED'
GROUP BY f.flight_id, f.flight_no, f.departure_at
HAVING coalesce(sum(fb.passengers), 0) < 5
ORDER BY f.departure_at;

-- @R09
-- Trends: 10 most-booked routes in June 2026
-- REWRITTEN: Explicit b.booking_type = 'FLIGHT' prunes hotel bookings during Index Only Scan
SELECT f.origin, f.destination, count(*) AS bookings, sum(fb.passengers) AS passengers
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE b.booked_at >= '2026-06-01' AND b.booked_at < '2026-07-01'
  AND b.booking_type = 'FLIGHT'
GROUP BY f.origin, f.destination
ORDER BY bookings DESC
LIMIT 10;

-- @R10
-- Flight status board: delayed flights
SELECT flight_id, flight_no, origin, destination, departure_at
FROM flights
WHERE status = 'DELAYED'
ORDER BY departure_at;

-- @R11
-- Payments: bookings waiting for payment for more than 30 minutes (checked at 23:59 on 30 Jun 2026)
SELECT booking_id, booking_ref, customer_id, total_amount, booked_at
FROM bookings
WHERE status = 'PENDING_PAYMENT'
  AND booked_at < TIMESTAMPTZ '2026-06-30 23:59:00+05:30' - interval '30 minutes'
ORDER BY booked_at;

-- @R12
-- Finance: revenue per booking type per month in 2026 (excluding cancellations)
-- REWRITTEN: Sargable timestamp range replaces EXTRACT(YEAR FROM booked_at) = 2026
SELECT date_trunc('month', booked_at) AS month, booking_type, count(*) AS bookings, sum(total_amount) AS revenue
FROM bookings
WHERE status <> 'CANCELLED'
  AND booked_at >= TIMESTAMPTZ '2026-01-01 00:00:00+05:30'
  AND booked_at <  TIMESTAMPTZ '2027-01-01 00:00:00+05:30'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R13
-- Marketing: coupons that have never been used
-- REWRITTEN: NOT EXISTS fixes the SQL NULL-absorption bug in NOT IN (returns 10 unused coupons instead of 0)
SELECT c.coupon_code, c.applies_to, c.discount_pct
FROM coupons c
WHERE NOT EXISTS (
    SELECT 1
    FROM bookings b
    WHERE b.coupon_code = c.coupon_code
      AND b.coupon_code IS NOT NULL
);

-- @R14
-- Airline partnerships: cancellation rate of flight bookings per airline
-- REWRITTEN: Reads concurrently-refreshable materialized view mv_airline_cancel_rates
SELECT airline_name, bookings, cancel_pct
FROM mv_airline_cancel_rates
ORDER BY cancel_pct DESC;

-- @R15
-- Hotel partnerships: room-nights sold per city for stays in June 2026
-- REWRITTEN: Explicit b.booking_type = 'HOTEL' enables Index Only Scan via idx_bookings_hotel_active
SELECT h.city_name,
       sum(hb.rooms * (least(hb.check_out, DATE '2026-07-01') - greatest(hb.check_in, DATE '2026-06-01'))) AS room_nights
FROM hotel_bookings hb
JOIN hotels h   ON h.hotel_id = hb.hotel_id
JOIN bookings b ON b.booking_id = hb.booking_id
               AND b.booking_type = 'HOTEL'
               AND b.status <> 'CANCELLED'
WHERE hb.check_in < '2026-07-01' AND hb.check_out > '2026-06-01'
GROUP BY h.city_name
ORDER BY room_nights DESC;

-- @R16
-- Insights: average days between booking and travel, per booking type and loyalty tier
-- REWRITTEN: Reads concurrently-refreshable materialized view mv_booking_lead_time
SELECT booking_type, loyalty_tier, avg_lead_days
FROM mv_booking_lead_time
ORDER BY 1, 2;

-- @R17
-- Loyalty: customers with 3 or more completed trips that started in 2026
SELECT b.customer_id, count(*) AS trips, sum(b.total_amount) AS spend
FROM bookings b
WHERE b.status = 'COMPLETED'
  AND b.booked_at >= '2026-01-01'
GROUP BY b.customer_id
HAVING count(*) >= 3
ORDER BY trips DESC, spend DESC;

-- @R18
-- Hotel page: Goa reviews that mention breakfast
SELECT r.review_id, h.hotel_name, r.rating, r.review_text
FROM hotel_reviews r
JOIN hotels h ON h.hotel_id = r.hotel_id
WHERE h.city_name = 'Goa'
  AND r.review_text ILIKE '%breakfast%'
ORDER BY r.created_at DESC
LIMIT 30;

-- @R19
-- Operations: passengers booked on every flight departing in June 2026
-- REWRITTEN: LEFT JOIN + GROUP BY eliminates the 720-loop correlated scalar subquery
SELECT f.flight_id, f.flight_no, f.departure_at,
       count(p.booking_id) AS passengers
FROM flights f
LEFT JOIN flight_bookings fb ON fb.flight_id = f.flight_id
LEFT JOIN passengers p       ON p.booking_id = fb.booking_id
WHERE f.departure_at >= '2026-06-01' AND f.departure_at < '2026-07-01'
GROUP BY f.flight_id, f.flight_no, f.departure_at
ORDER BY passengers DESC, f.departure_at;

-- @R20
-- Finance: bookings per day and running total for June 2026
-- REWRITTEN: Sargable timestamp range replaces booked_at::date BETWEEN
SELECT day, bookings, sum(bookings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT booked_at::date AS day, count(*) AS bookings
    FROM bookings
    WHERE booked_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
      AND booked_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Concessions: senior-citizen passengers (60+) per route in 2026
SELECT f.origin, f.destination, count(*) AS senior_passengers
FROM passengers p
JOIN flight_bookings fb ON fb.booking_id = p.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE p.age >= 60
  AND f.departure_at >= '2026-01-01'
GROUP BY f.origin, f.destination
ORDER BY senior_passengers DESC;

-- @R22
-- Support console: all bookings, newest first, page 4,001 (25 per page)
-- REWRITTEN: Keyset pagination anchored at the last row of page 4,000 (2025-06-18 22:17:24+05:30, booking_id 46410)
SELECT booking_id, booking_ref, booking_type, status, total_amount, booked_at
FROM bookings
WHERE (booked_at, booking_id) < (TIMESTAMPTZ '2025-06-18 22:17:24+05:30', 46410)
ORDER BY booked_at DESC, booking_id DESC
LIMIT 25;

-- @R23
-- Sign-in: find the customer by email, ignoring case
SELECT customer_id, full_name, loyalty_tier
FROM customers
WHERE lower(email) = 'siddharth.sharma1021@rediffmail.com';

-- @R24
-- Hotel ranking: Goa hotels with at least 5 reviews, by average review rating
SELECT h.hotel_id, h.hotel_name, round(avg(r.rating), 2) AS avg_rating, count(*) AS reviews
FROM hotels h
JOIN hotel_reviews r ON r.hotel_id = h.hotel_id
WHERE h.city_name = 'Goa'
GROUP BY h.hotel_id, h.hotel_name
HAVING count(*) >= 5
ORDER BY avg_rating DESC, reviews DESC
LIMIT 20;

-- @R25
-- Insights: last-minute flight bookings (made less than 24 hours before departure) in 2026
-- REWRITTEN: Explicit b.booking_type = 'FLIGHT' and f.departure_at >= '2026-01-01' range pruning
SELECT b.booking_id, b.booked_at, f.departure_at, f.origin, f.destination
FROM bookings b
JOIN flight_bookings fb ON fb.booking_id = b.booking_id
JOIN flights f          ON f.flight_id = fb.flight_id
WHERE f.departure_at - b.booked_at < interval '24 hours'
  AND b.booked_at >= '2026-01-01'
  AND b.booking_type = 'FLIGHT'
  AND f.departure_at >= '2026-01-01'
ORDER BY b.booked_at DESC;

-- @W01
-- Checkout: create a pending flight booking for customer 1021
INSERT INTO bookings (booking_id, booking_ref, customer_id, booking_type, booked_at, total_amount, payment_method, status)
VALUES (90000001, 'MMZZ0001', 1021, 'FLIGHT', '2026-07-01 10:00:00+05:30', 5400.00, 'UPI', 'PENDING_PAYMENT');

-- @W02
-- Payment gateway callback: confirm the oldest booking that is waiting for payment
UPDATE bookings
SET status = 'CONFIRMED'
WHERE booking_id = (SELECT min(booking_id) FROM bookings WHERE status = 'PENDING_PAYMENT');

-- @W03
-- Customer cancels booking MMA7772F with a 70% refund
UPDATE bookings
SET status = 'CANCELLED', cancelled_at = '2026-07-01 11:00:00+05:30', refund_amount = round(total_amount * 0.7, 2)
WHERE booking_ref = 'MMA7772F' AND status <> 'CANCELLED';

-- @W04
-- Flight ops: every flight that was scheduled to depart before 1 July 2026 has now departed
UPDATE flights
SET status = 'DEPARTED'
WHERE status IN ('SCHEDULED', 'DELAYED')
  AND departure_at < '2026-07-01 00:00:00+05:30';

-- @W05
-- Front desk: assign room numbers to every guest checking in on 1 July 2026
UPDATE hotel_bookings hb
SET room_number = (100 + hb.booking_id % 400)::text
FROM bookings b
WHERE b.booking_id = hb.booking_id
  AND b.status = 'CONFIRMED'
  AND hb.check_in = '2026-07-01'
  AND hb.room_number IS NULL;

-- @END
ROLLBACK;
