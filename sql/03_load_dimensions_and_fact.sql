/*
================================================================================
 03 - Load dimensions and fact (Build, Q3)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Loads dw.DimDate, DimAirport, DimAircraft, DimPassenger, DimFlight from the
bronze_* tables, then loads dw.FactTicketSales by joining bronze_bookings to
every dimension on its business key.
*/

USE VayuAir;
GO

-- ----------------------------------------------------------------------------
-- DimDate: one row per calendar day, 2024-01-01 .. 2026-12-31. Wide enough to
-- comfortably cover booking_date (min 2024-11-02), travel_date/flight_date
-- (2025-01-01 .. 2026-03-31) and headroom for future loads.
-- DateKey = YEAR(d)*10000 + MONTH(d)*100 + DAY(d), per the hint.
--
-- Uses DELETE, not TRUNCATE, here and on every other dimension below:
-- TRUNCATE TABLE refuses to run on any table a FOREIGN KEY references,
-- even one with zero matching rows - and FactTicketSales/DimFlight/
-- DimPassenger all reference these dimensions. FactTicketSales itself has
-- nothing referencing it, so it keeps TRUNCATE further down.
-- ----------------------------------------------------------------------------
DELETE FROM dw.DimDate;

WITH Digits AS (
    SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
),
Tally AS (
    SELECT TOP (1100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM Digits a, Digits b, Digits c, Digits d
),
Dates AS (
    SELECT DATEADD(DAY, n, CAST('2024-01-01' AS DATE)) AS FullDate
    FROM Tally
    WHERE DATEADD(DAY, n, CAST('2024-01-01' AS DATE)) <= '2026-12-31'
)
INSERT INTO dw.DimDate (DateKey, FullDate, [Year], [Quarter], MonthNumber, MonthName, [Day], DayName, IsWeekend)
SELECT
    YEAR(FullDate) * 10000 + MONTH(FullDate) * 100 + DAY(FullDate) AS DateKey,
    FullDate,
    YEAR(FullDate),
    DATEPART(QUARTER, FullDate),
    MONTH(FullDate),
    DATENAME(MONTH, FullDate),
    DAY(FullDate),
    DATENAME(WEEKDAY, FullDate),
    CASE WHEN DATENAME(WEEKDAY, FullDate) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
FROM Dates;
GO

-- ----------------------------------------------------------------------------
-- DimAirport (flat, pre-snowflake)
-- ----------------------------------------------------------------------------
DELETE FROM dw.DimAirport;

INSERT INTO dw.DimAirport (AirportCode, AirportName, City, Country, Region)
SELECT airport_code, airport_name, city, country, region
FROM bronze_airports;
GO

-- ----------------------------------------------------------------------------
-- DimAircraft
-- ----------------------------------------------------------------------------
DELETE FROM dw.DimAircraft;

INSERT INTO dw.DimAircraft (AircraftCode, Model, Manufacturer, SeatCapacity)
SELECT aircraft_code, model, manufacturer, seat_capacity
FROM bronze_aircraft;
GO

-- ----------------------------------------------------------------------------
-- DimPassenger (plain, pre-SCD2)
-- ----------------------------------------------------------------------------
DELETE FROM dw.DimPassenger;

INSERT INTO dw.DimPassenger (PassengerID, PassengerName, HomeAirportKey, FrequentFlyerTier, SignupDate)
SELECT
    p.passenger_id,
    p.passenger_name,
    a.AirportKey,
    p.frequent_flyer_tier,
    p.signup_date
FROM bronze_passengers p
JOIN dw.DimAirport a ON a.AirportCode = p.home_airport_code;
GO

-- ----------------------------------------------------------------------------
-- DimFlight
-- ----------------------------------------------------------------------------
DELETE FROM dw.DimFlight;

INSERT INTO dw.DimFlight (FlightID, FlightNumber, OriginAirportKey, DestAirportKey, AircraftKey, FlightDate)
SELECT
    f.flight_id,
    f.flight_number,
    orig.AirportKey,
    dest.AirportKey,
    ac.AircraftKey,
    f.flight_date
FROM bronze_flights f
JOIN dw.DimAirport  orig ON orig.AirportCode = f.origin_airport_code
JOIN dw.DimAirport  dest ON dest.AirportCode = f.dest_airport_code
JOIN dw.DimAircraft ac   ON ac.AircraftCode  = f.aircraft_code;
GO

-- ----------------------------------------------------------------------------
-- FactTicketSales - join bronze_bookings to every dimension on its business
-- key. Inner joins throughout are intentional: every FK in bronze_bookings
-- and bronze_flights is validated (03_How_to_Import_Data / 04_Data
-- Dictionary) to always resolve, so an inner join that silently dropped
-- rows would itself be a red flag worth investigating, not something to
-- mask with a LEFT JOIN.
-- ----------------------------------------------------------------------------
TRUNCATE TABLE dw.FactTicketSales;

INSERT INTO dw.FactTicketSales (
    BookingID, BookingDateKey, TravelDateKey, PassengerKey, FlightKey,
    FareClass, BookingStatus, FareAmount, TaxAmount, MilesEarned
)
SELECT
    b.booking_id,
    dBook.DateKey,
    dTravel.DateKey,
    p.PassengerKey,
    f.FlightKey,
    b.fare_class,
    b.booking_status,
    b.fare_amount,
    b.tax_amount,
    b.miles_earned
FROM bronze_bookings b
JOIN dw.DimDate      dBook   ON dBook.FullDate   = b.booking_date
JOIN dw.DimDate      dTravel ON dTravel.FullDate = b.travel_date
JOIN dw.DimPassenger p       ON p.PassengerID    = b.passenger_id
JOIN dw.DimFlight    f       ON f.FlightID       = b.flight_id;
GO

-- ----------------------------------------------------------------------------
-- Verification: acceptance criteria for Q3.
-- ----------------------------------------------------------------------------
-- 1. Fact row count must match bronze_bookings (40,000).
SELECT
    (SELECT COUNT(*) FROM bronze_bookings)      AS bronze_bookings_rows,
    (SELECT COUNT(*) FROM dw.FactTicketSales)   AS fact_rows;

-- 2. Every fact row must resolve to all of its dimensions (no orphan FKs).
SELECT
    (SELECT COUNT(*) FROM dw.FactTicketSales f WHERE NOT EXISTS (SELECT 1 FROM dw.DimDate d WHERE d.DateKey = f.BookingDateKey)) AS orphan_booking_date,
    (SELECT COUNT(*) FROM dw.FactTicketSales f WHERE NOT EXISTS (SELECT 1 FROM dw.DimDate d WHERE d.DateKey = f.TravelDateKey))  AS orphan_travel_date,
    (SELECT COUNT(*) FROM dw.FactTicketSales f WHERE NOT EXISTS (SELECT 1 FROM dw.DimPassenger p WHERE p.PassengerKey = f.PassengerKey)) AS orphan_passenger,
    (SELECT COUNT(*) FROM dw.FactTicketSales f WHERE NOT EXISTS (SELECT 1 FROM dw.DimFlight fl WHERE fl.FlightKey = f.FlightKey)) AS orphan_flight;
-- All four orphan counts, and the row-count gap above, are expected to be 0.
