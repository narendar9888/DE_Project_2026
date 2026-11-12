-- MakeMyTrip DBMS Project — Phase 2 schema
-- PostgreSQL 15+
-- Run from an empty database. This file creates constraints only (no tuning indexes).

CREATE SCHEMA IF NOT EXISTS mmt;
SET search_path TO mmt;

CREATE TABLE airports (
    iata_code       VARCHAR(3) PRIMARY KEY,
    airport_name    VARCHAR(150) NOT NULL,
    city_name       VARCHAR(100) NOT NULL,
    country_code    VARCHAR(2) NOT NULL,
    CONSTRAINT airports_iata_format_ck CHECK (iata_code ~ '^[A-Z]{3}$'),
    CONSTRAINT airports_country_format_ck CHECK (country_code ~ '^[A-Z]{2}$')
);

CREATE TABLE airlines (
    airline_code    VARCHAR(3) PRIMARY KEY,
    airline_name    VARCHAR(120) NOT NULL,
    CONSTRAINT airlines_code_format_ck CHECK (airline_code ~ '^[A-Z0-9]{2,3}$')
);

CREATE TABLE flights (
    flight_id       INTEGER PRIMARY KEY,
    airline_code    VARCHAR(3) NOT NULL REFERENCES airlines(airline_code) ON UPDATE CASCADE ON DELETE RESTRICT,
    flight_no       VARCHAR(12) NOT NULL,
    origin          VARCHAR(3) NOT NULL REFERENCES airports(iata_code) ON UPDATE CASCADE ON DELETE RESTRICT,
    destination     VARCHAR(3) NOT NULL REFERENCES airports(iata_code) ON UPDATE CASCADE ON DELETE RESTRICT,
    departure_at    TIMESTAMPTZ NOT NULL,
    arrival_at      TIMESTAMPTZ NOT NULL,
    aircraft        VARCHAR(40),
    total_seats     SMALLINT NOT NULL,
    base_fare       NUMERIC(10,2) NOT NULL,
    status          VARCHAR(20) NOT NULL,
    CONSTRAINT flights_route_ck CHECK (origin <> destination),
    CONSTRAINT flights_time_ck CHECK (arrival_at > departure_at),
    CONSTRAINT flights_seats_ck CHECK (total_seats > 0),
    CONSTRAINT flights_fare_ck CHECK (base_fare >= 0),
    CONSTRAINT flights_number_ck CHECK (flight_no ~ '^[A-Z0-9-]+$')
);

CREATE TABLE hotels (
    hotel_id        INTEGER PRIMARY KEY,
    hotel_name      VARCHAR(180) NOT NULL,
    city_name       VARCHAR(100) NOT NULL,
    star_rating     SMALLINT,
    user_rating     NUMERIC(2,1),
    amenities       JSONB NOT NULL,
    check_in_time   TIME NOT NULL,
    check_out_time  TIME NOT NULL,
    CONSTRAINT hotels_star_rating_ck CHECK (star_rating BETWEEN 1 AND 5),
    CONSTRAINT hotels_user_rating_ck CHECK (user_rating BETWEEN 0 AND 5),
    CONSTRAINT hotels_amenities_object_ck CHECK (jsonb_typeof(amenities) = 'object')
);

CREATE TABLE room_types (
    room_type_id    INTEGER PRIMARY KEY,
    hotel_id        INTEGER NOT NULL REFERENCES hotels(hotel_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    room_name       VARCHAR(100) NOT NULL,
    max_guests      SMALLINT NOT NULL,
    price_per_night NUMERIC(10,2) NOT NULL,
    total_rooms     SMALLINT NOT NULL,
    CONSTRAINT room_types_guests_ck CHECK (max_guests > 0),
    CONSTRAINT room_types_price_ck CHECK (price_per_night >= 0),
    CONSTRAINT room_types_count_ck CHECK (total_rooms > 0),
    CONSTRAINT room_types_id_hotel_uq UNIQUE (room_type_id, hotel_id)
);

CREATE TABLE customers (
    customer_id     INTEGER PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(254) NOT NULL,
    phone           VARCHAR(20),
    loyalty_tier    VARCHAR(20) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT customers_email_nonempty_ck CHECK (length(trim(email)) > 0),
    CONSTRAINT customers_email_shape_ck CHECK (email ~* '^[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$'),
    CONSTRAINT customers_phone_nonempty_ck CHECK (phone IS NULL OR length(trim(phone)) > 0),
    CONSTRAINT customers_loyalty_nonempty_ck CHECK (length(trim(loyalty_tier)) > 0)
);

CREATE TABLE coupons (
    coupon_code     VARCHAR(30) PRIMARY KEY,
    applies_to      VARCHAR(10) NOT NULL,
    discount_pct    NUMERIC(5,2) NOT NULL,
    max_discount    NUMERIC(10,2) NOT NULL,
    valid_from      DATE NOT NULL,
    valid_to        DATE NOT NULL,
    CONSTRAINT coupons_applies_to_ck CHECK (applies_to IN ('FLIGHT', 'HOTEL', 'ALL')),
    CONSTRAINT coupons_discount_pct_ck CHECK (discount_pct > 0 AND discount_pct <= 100),
    CONSTRAINT coupons_max_discount_ck CHECK (max_discount >= 0),
    CONSTRAINT coupons_validity_ck CHECK (valid_to >= valid_from)
);

CREATE TABLE bookings (
    booking_id      INTEGER PRIMARY KEY,
    booking_ref     VARCHAR(20) NOT NULL UNIQUE,
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    booking_type    VARCHAR(10) NOT NULL,
    booked_at       TIMESTAMPTZ NOT NULL,
    total_amount    NUMERIC(12,2) NOT NULL,
    coupon_code     VARCHAR(30) REFERENCES coupons(coupon_code) ON UPDATE CASCADE ON DELETE SET NULL,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0,
    payment_method  VARCHAR(30) NOT NULL,
    status          VARCHAR(30) NOT NULL,
    cancelled_at    TIMESTAMPTZ,
    refund_amount   NUMERIC(12,2),
    CONSTRAINT bookings_type_ck CHECK (booking_type IN ('FLIGHT', 'HOTEL')),
    CONSTRAINT bookings_amount_ck CHECK (total_amount >= 0),
    CONSTRAINT bookings_discount_ck CHECK (discount >= 0 AND discount <= total_amount),
    CONSTRAINT bookings_ref_nonempty_ck CHECK (length(trim(booking_ref)) > 0),
    CONSTRAINT bookings_payment_nonempty_ck CHECK (length(trim(payment_method)) > 0),
    CONSTRAINT bookings_status_nonempty_ck CHECK (length(trim(status)) > 0),
    CONSTRAINT bookings_coupon_discount_ck CHECK (coupon_code IS NOT NULL OR discount = 0),
    CONSTRAINT bookings_cancel_refund_ck CHECK (
        (cancelled_at IS NULL AND (refund_amount IS NULL OR refund_amount = 0))
        OR
        (cancelled_at IS NOT NULL AND refund_amount IS NOT NULL AND refund_amount >= 0 AND refund_amount <= total_amount)
    )
);

CREATE TABLE flight_bookings (
    booking_id      INTEGER PRIMARY KEY REFERENCES bookings(booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    flight_id       INTEGER NOT NULL REFERENCES flights(flight_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    cabin           VARCHAR(20) NOT NULL,
    passengers      SMALLINT NOT NULL,
    fare_paid       NUMERIC(12,2) NOT NULL,
    CONSTRAINT flight_bookings_passengers_ck CHECK (passengers > 0),
    CONSTRAINT flight_bookings_fare_ck CHECK (fare_paid >= 0),
    CONSTRAINT flight_bookings_cabin_nonempty_ck CHECK (length(trim(cabin)) > 0)
);

CREATE TABLE passengers (
    booking_id      INTEGER NOT NULL REFERENCES flight_bookings(booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    seq_no          SMALLINT NOT NULL,
    full_name       VARCHAR(150) NOT NULL,
    age             SMALLINT,
    gender          VARCHAR(10),
    seat_no         VARCHAR(8),
    CONSTRAINT passengers_pk PRIMARY KEY (booking_id, seq_no),
    CONSTRAINT passengers_seq_ck CHECK (seq_no > 0),
    CONSTRAINT passengers_age_ck CHECK (age IS NULL OR age BETWEEN 0 AND 120),
    CONSTRAINT passengers_name_ck CHECK (length(trim(full_name)) > 0),
    CONSTRAINT passengers_seat_nonempty_ck CHECK (seat_no IS NULL OR length(trim(seat_no)) > 0)
);

CREATE TABLE hotel_bookings (
    booking_id      INTEGER PRIMARY KEY REFERENCES bookings(booking_id) ON UPDATE CASCADE ON DELETE CASCADE,
    hotel_id        INTEGER NOT NULL REFERENCES hotels(hotel_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    room_type_id    INTEGER NOT NULL,
    check_in        DATE NOT NULL,
    check_out       DATE NOT NULL,
    rooms           SMALLINT NOT NULL,
    guests          SMALLINT NOT NULL,
    room_number     VARCHAR(20),
    CONSTRAINT hotel_bookings_room_hotel_fk
        FOREIGN KEY (room_type_id, hotel_id)
        REFERENCES room_types(room_type_id, hotel_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT hotel_bookings_dates_ck CHECK (check_out > check_in),
    CONSTRAINT hotel_bookings_rooms_ck CHECK (rooms > 0),
    CONSTRAINT hotel_bookings_guests_ck CHECK (guests > 0),
    CONSTRAINT hotel_bookings_room_number_ck CHECK (room_number IS NULL OR length(trim(room_number)) > 0),
    CONSTRAINT hotel_bookings_id_hotel_uq UNIQUE (booking_id, hotel_id)
);

CREATE TABLE hotel_reviews (
    review_id       INTEGER PRIMARY KEY,
    booking_id      INTEGER NOT NULL,
    hotel_id        INTEGER NOT NULL,
    rating          SMALLINT NOT NULL,
    title           VARCHAR(200) NOT NULL,
    review_text     TEXT,
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT hotel_reviews_booking_hotel_fk
        FOREIGN KEY (booking_id, hotel_id)
        REFERENCES hotel_bookings(booking_id, hotel_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT hotel_reviews_rating_ck CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT hotel_reviews_title_ck CHECK (length(trim(title)) > 0)
);


