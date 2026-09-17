/*
================================================================================
 02 - Star schema DDL (Design, Q2)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Grain (from 01): one row in dw.FactTicketSales = one ticket sold
(one booking_id).

DimAirport is deliberately flat (denormalised) here - it gets snowflaked
into DimAirport/DimCity/DimCountry in 04, after the base star is working.
DimPassenger is deliberately a plain, current-state dimension here - it
gets rebuilt as SCD Type 2 in 05.

Every dimension has an IDENTITY surrogate key plus its original source
column kept as a business key (unique, so bronze rows can always be
re-matched to their dimension row).
*/

USE VayuAir;
GO

IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO

IF OBJECT_ID('dw.FactTicketSales', 'U') IS NOT NULL DROP TABLE dw.FactTicketSales;
IF OBJECT_ID('dw.DimFlight', 'U') IS NOT NULL DROP TABLE dw.DimFlight;
IF OBJECT_ID('dw.DimPassenger', 'U') IS NOT NULL DROP TABLE dw.DimPassenger;
IF OBJECT_ID('dw.DimAirport', 'U') IS NOT NULL DROP TABLE dw.DimAirport;
IF OBJECT_ID('dw.DimAircraft', 'U') IS NOT NULL DROP TABLE dw.DimAircraft;
IF OBJECT_ID('dw.DimDate', 'U') IS NOT NULL DROP TABLE dw.DimDate;
GO

-- ----------------------------------------------------------------------------
-- DimDate - conformed, role-playing dimension (used as both "booked on" and
-- "travelled on" via two FKs from the fact). Surrogate key IS the business
-- key here (yyyymmdd int), which is the standard, deliberate exception to
-- "always use an IDENTITY surrogate" for date dimensions: it's human-
-- readable, sorts correctly, and needs no lookup to build during ETL.
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimDate (
    DateKey         INT          NOT NULL PRIMARY KEY,   -- yyyymmdd, e.g. 20250714
    FullDate        DATE         NOT NULL,
    [Year]          SMALLINT     NOT NULL,
    [Quarter]       TINYINT      NOT NULL,
    MonthNumber     TINYINT      NOT NULL,
    MonthName       VARCHAR(9)   NOT NULL,
    [Day]           TINYINT      NOT NULL,
    DayName         VARCHAR(9)   NOT NULL,
    IsWeekend       BIT          NOT NULL,
    CONSTRAINT UQ_DimDate_FullDate UNIQUE (FullDate)
);
GO

-- ----------------------------------------------------------------------------
-- DimAirport - flat for now (snowflaked in 04)
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimAirport (
    AirportKey      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AirportCode     CHAR(3)      NOT NULL,
    AirportName     VARCHAR(100) NOT NULL,
    City            VARCHAR(100) NOT NULL,
    Country         VARCHAR(100) NOT NULL,
    Region          VARCHAR(50)  NOT NULL,
    CONSTRAINT UQ_DimAirport_Code UNIQUE (AirportCode)
);
GO

-- ----------------------------------------------------------------------------
-- DimAircraft
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimAircraft (
    AircraftKey     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    AircraftCode    VARCHAR(20)  NOT NULL,
    Model           VARCHAR(50)  NOT NULL,
    Manufacturer    VARCHAR(50)  NOT NULL,
    SeatCapacity    INT          NOT NULL,
    CONSTRAINT UQ_DimAircraft_Code UNIQUE (AircraftCode)
);
GO

-- ----------------------------------------------------------------------------
-- DimPassenger - plain current-state dimension for now (rebuilt as SCD2 in 05)
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimPassenger (
    PassengerKey        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    PassengerID          BIGINT       NOT NULL,
    PassengerName         VARCHAR(100) NOT NULL,
    HomeAirportKey        INT          NOT NULL,
    FrequentFlyerTier     VARCHAR(20)  NOT NULL,
    SignupDate            DATE         NOT NULL,
    CONSTRAINT UQ_DimPassenger_PassengerID UNIQUE (PassengerID),
    CONSTRAINT FK_DimPassenger_HomeAirport FOREIGN KEY (HomeAirportKey) REFERENCES dw.DimAirport (AirportKey)
);
GO

-- ----------------------------------------------------------------------------
-- DimFlight
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimFlight (
    FlightKey        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    FlightID          BIGINT       NOT NULL,
    FlightNumber      VARCHAR(10)  NOT NULL,
    OriginAirportKey  INT          NOT NULL,
    DestAirportKey    INT          NOT NULL,
    AircraftKey       INT          NOT NULL,
    FlightDate        DATE         NOT NULL,
    CONSTRAINT UQ_DimFlight_FlightID UNIQUE (FlightID),
    CONSTRAINT FK_DimFlight_Origin   FOREIGN KEY (OriginAirportKey) REFERENCES dw.DimAirport (AirportKey),
    CONSTRAINT FK_DimFlight_Dest     FOREIGN KEY (DestAirportKey)   REFERENCES dw.DimAirport (AirportKey),
    CONSTRAINT FK_DimFlight_Aircraft FOREIGN KEY (AircraftKey)      REFERENCES dw.DimAircraft (AircraftKey)
);
GO

-- ----------------------------------------------------------------------------
-- FactTicketSales - grain: one row = one booking (one ticket sold).
-- Only additive measures live here (see 01). fare_class and booking_status
-- are low-cardinality attributes with no attributes of their own, so they
-- stay directly on the fact instead of becoming degenerate dimensions.
-- BookingID is the natural key and, since the grain is 1:1 with bookings,
-- doubles as the fact's primary key - no extra surrogate key is needed.
-- ----------------------------------------------------------------------------
CREATE TABLE dw.FactTicketSales (
    BookingID        BIGINT        NOT NULL PRIMARY KEY,
    BookingDateKey    INT          NOT NULL,   -- role-playing FK #1: "booked on"
    TravelDateKey     INT          NOT NULL,   -- role-playing FK #2: "travelled on"
    PassengerKey      INT          NOT NULL,
    FlightKey         INT          NOT NULL,
    FareClass         VARCHAR(20)  NOT NULL,
    BookingStatus     VARCHAR(20)  NOT NULL,
    FareAmount        DECIMAL(18,2) NOT NULL,
    TaxAmount         DECIMAL(18,2) NOT NULL,
    MilesEarned       INT          NOT NULL,
    CONSTRAINT FK_Fact_BookingDate FOREIGN KEY (BookingDateKey) REFERENCES dw.DimDate (DateKey),
    CONSTRAINT FK_Fact_TravelDate  FOREIGN KEY (TravelDateKey)  REFERENCES dw.DimDate (DateKey),
    CONSTRAINT FK_Fact_Passenger   FOREIGN KEY (PassengerKey)   REFERENCES dw.DimPassenger (PassengerKey),
    CONSTRAINT FK_Fact_Flight      FOREIGN KEY (FlightKey)      REFERENCES dw.DimFlight (FlightKey)
);
GO
