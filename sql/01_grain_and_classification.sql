/*
================================================================================
 01 - Grain statement and column classification (Design, Q1)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
No DDL/DML here on purpose - this question asks for the grain declaration
and the dimension-key/measure split, written as comments, before any table
gets built. Everything downstream (02 onward) implements this decision.
*/

-- ============================================================================
-- GRAIN
-- ============================================================================
-- One row in FactTicketSales = one ticket sold: a single booking_id, i.e.
-- one passenger's seat on one flight. bronze_bookings is already at this
-- grain 1:1 (booking_id is unique, 40,000 rows), so the fact does not need
-- to roll up or fan out bookings - it is a straight, enriched copy of
-- bronze_bookings joined out to its dimensions.
--
-- Explicitly NOT the grain: not one row per passenger, not one row per
-- flight, not one row per passenger-per-day. A passenger with 3 bookings
-- on 3 different flights contributes 3 fact rows.

-- ============================================================================
-- COLUMN CLASSIFICATION
-- bronze_bookings joined to its flight (bronze_flights via flight_id)
-- ============================================================================
-- column                  | classification         | notes
-- ------------------------|-------------------------|----------------------------------------------------
-- booking_id              | dimension key           | degenerate dimension - the grain-defining natural key, kept on the fact, not modeled as its own table
-- passenger_id            | dimension key           | FK to DimPassenger (business key)
-- flight_id               | dimension key           | FK to DimFlight (business key)
-- booking_date            | dimension key           | FK to DimDate (role-playing: "booked on")
-- travel_date             | dimension key           | FK to DimDate (role-playing: "travelled on"); always equals the flight's own flight_date in this data
-- fare_class               | dimension key (attribute) | only 4 fixed values (Economy/Premium Economy/Business/First) with no attributes of their own - kept directly on the fact rather than spun into its own dimension table
-- booking_status           | dimension key (attribute) | Confirmed/Cancelled/NoShow - a status flag, used to filter revenue, not to sum
-- fare_amount              | measure                | additive
-- tax_amount               | measure                | additive
-- miles_earned             | measure                | additive
-- -- from bronze_flights (joined via flight_id) --
-- flight_number            | dimension attribute     | attribute of DimFlight
-- origin_airport_code      | dimension key           | FK to DimAirport (via DimFlight)
-- dest_airport_code        | dimension key           | FK to DimAirport (via DimFlight)
-- aircraft_code            | dimension key           | FK to DimAircraft (via DimFlight)
-- flight_date              | dimension attribute     | kept on DimFlight; not re-used as a fact FK because it is identical to travel_date for every booking on that flight

-- ============================================================================
-- ADDITIVE VS NON-ADDITIVE
-- ============================================================================
-- fare_amount, tax_amount and miles_earned are all additive: they sum
-- correctly across any combination of dimensions (total fare collected in a
-- month, total miles issued by route, etc.).
--
-- A value that would NOT be additive: an average, e.g. average fare_amount
-- per booking (or a rate like fare_amount / miles_earned). Summing an
-- average across passengers or months produces a meaningless number - it
-- has to be recomputed as SUM(fare_amount) / COUNT(*) at whatever grain
-- you're reporting, never stored and summed directly.
