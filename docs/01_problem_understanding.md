# Phase 1 — Problem Understanding

**Project:** MakeMyTrip Travel Booking Database  
**Database:** PostgreSQL 15+  
**Scope:** Flight bookings, hotel bookings, customers, payments, coupons and reviews.

## Business problems

| ID | Business need in plain language | Main stakeholders | Classification |
|---|---|---|---|
| P1 | Search flights by route/date, show the fare calendar and calculate seats remaining accurately. | Traveller, flight operations, revenue management | Customer-facing / real-time |
| P2 | Find hotels by city, rating and amenities, and show room availability for a requested date range. | Traveller, hotel partner, front desk | Customer-facing / real-time |
| P3 | Load a customer's trips quickly, find a booking from its reference and locate an account during sign-in. | Traveller, customer support | Customer-facing / real-time |
| P4 | Produce passenger manifests, identify lightly booked flights and measure airline cancellation rates. | Airline partner, flight operations | Reporting / analytics (manifest can be operational) |
| P5 | Process pending payments, confirmations, cancellations and refunds reliably during high traffic. | Traveller, payments team, customer support | Customer-facing / real-time |
| P6 | Identify coupons that have never been redeemed so marketing can evaluate campaigns. | Marketing | Reporting / analytics |
| P7 | Calculate room-nights sold by city and support check-in room assignment. | Hotel partner, front desk | Reporting / analytics + operational |
| P8 | Produce revenue, lead-time, loyalty, last-minute booking, route and concession reports while supporting substantial growth. | Finance, loyalty, insights, management | Reporting / analytics |

## Assumptions

1. Each row in `flights` represents one dated flight instance, not a reusable airline timetable.
2. Each booking has exactly one customer and one booking type: `FLIGHT` or `HOTEL`.
3. A flight booking refers to one flight instance and can contain multiple passenger rows.
4. A hotel booking refers to one hotel and one room type; `rooms` and `guests` describe the reservation.
5. A room number is assigned at check-in, so it can be NULL before check-in.
6. A passenger seat is assigned at web check-in, so `seat_no` can be NULL beforehand.
7. Coupon use is optional. Cancellation timestamp and refund are optional for bookings that have not been cancelled.
8. The source CSV exports are the authority for source values. Constraints should reject invalid business data without assuming undocumented enum values.
9. Search and operational queries need current data; aggregate reports can be optimized separately in later phases.
10. Phase 2 creates relational constraints only. Performance indexes beyond PostgreSQL's automatic PK/UNIQUE indexes belong to Phase 4.
