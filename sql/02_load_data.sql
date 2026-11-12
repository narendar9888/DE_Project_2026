\set ON_ERROR_STOP on
SET search_path TO mmt;


\copy airports FROM 'seed_data/airports.csv' WITH (FORMAT csv, HEADER true)
\copy airlines FROM 'seed_data/airlines.csv' WITH (FORMAT csv, HEADER true)
\copy hotels FROM 'seed_data/hotels.csv' WITH (FORMAT csv, HEADER true)
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)
\copy coupons FROM 'seed_data/coupons.csv' WITH (FORMAT csv, HEADER true)


\copy flights FROM 'seed_data/flights.csv' WITH (FORMAT csv, HEADER true)
\copy room_types FROM 'seed_data/room_types.csv' WITH (FORMAT csv, HEADER true)
\copy bookings FROM 'seed_data/bookings.csv' WITH (FORMAT csv, HEADER true)


\copy flight_bookings FROM 'seed_data/flight_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_bookings FROM 'seed_data/hotel_bookings.csv' WITH (FORMAT csv, HEADER true)
\copy passengers FROM 'seed_data/passengers.csv' WITH (FORMAT csv, HEADER true)
\copy hotel_reviews FROM 'seed_data/hotel_reviews.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;


SELECT 'airports' AS table_name, count(*) AS actual_rows, 16 AS expected_rows FROM mmt.airports
UNION ALL SELECT 'airlines', count(*), 5 FROM mmt.airlines
UNION ALL SELECT 'flights', count(*), 13848 FROM mmt.flights
UNION ALL SELECT 'hotels', count(*), 3000 FROM mmt.hotels
UNION ALL SELECT 'room_types', count(*), 9000 FROM mmt.room_types
UNION ALL SELECT 'customers', count(*), 40000 FROM mmt.customers
UNION ALL SELECT 'coupons', count(*), 30 FROM mmt.coupons
UNION ALL SELECT 'bookings', count(*), 144792 FROM mmt.bookings
UNION ALL SELECT 'flight_bookings', count(*), 84899 FROM mmt.flight_bookings
UNION ALL SELECT 'passengers', count(*), 163380 FROM mmt.passengers
UNION ALL SELECT 'hotel_bookings', count(*), 59893 FROM mmt.hotel_bookings
UNION ALL SELECT 'hotel_reviews', count(*), 15913 FROM mmt.hotel_reviews
ORDER BY table_name;


SELECT count(*) AS invalid_booking_subtypes
FROM mmt.bookings b
LEFT JOIN mmt.flight_bookings fb USING (booking_id)
LEFT JOIN mmt.hotel_bookings hb USING (booking_id)
WHERE (b.booking_type = 'FLIGHT' AND (fb.booking_id IS NULL OR hb.booking_id IS NOT NULL))
   OR (b.booking_type = 'HOTEL' AND (hb.booking_id IS NULL OR fb.booking_id IS NOT NULL));

SELECT count(*) AS passenger_count_mismatches
FROM mmt.flight_bookings fb
LEFT JOIN mmt.passengers p USING (booking_id)
GROUP BY fb.booking_id, fb.passengers
HAVING fb.passengers <> count(p.seq_no);


SELECT count(*) AS invalid_flight_booking_types
FROM mmt.flight_bookings fb
JOIN mmt.bookings b USING (booking_id)
WHERE b.booking_type <> 'FLIGHT';


SELECT count(*) AS invalid_hotel_booking_types
FROM mmt.hotel_bookings hb
JOIN mmt.bookings b USING (booking_id)
WHERE b.booking_type <> 'HOTEL';


SELECT count(*) AS coupon_rule_violations
FROM mmt.bookings b
JOIN mmt.coupons c USING (coupon_code)
WHERE c.applies_to NOT IN ('ALL', b.booking_type)
   OR b.booked_at::date NOT BETWEEN c.valid_from AND c.valid_to;


SELECT count(*) AS bookings_after_departure
FROM mmt.bookings b
JOIN mmt.flight_bookings fb USING (booking_id)
JOIN mmt.flights f USING (flight_id)
WHERE b.booked_at >= f.departure_at;
