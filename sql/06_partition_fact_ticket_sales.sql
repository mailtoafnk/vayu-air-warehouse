/*
================================================================================
 06 - Partition FactTicketSales by date (Build, Q6)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Partitions the fact by TravelDateKey (the date a passenger actually flew -
the natural axis for "sales by travel period" reporting on an airline
warehouse; BookingDateKey was the other candidate, see README).

Boundaries are monthly, RANGE RIGHT, from 2025-01-01 to 2026-04-01 - the
exact span of travel_date in this data (2025-01-01 .. 2026-03-31), so every
month of real data gets its own partition and there's one empty catch-all
partition on each end for anything outside that range.

SQL Server requires the partitioning column to be part of any unique/
clustered index used to place the table on the scheme, so the clustered PK
becomes the composite (TravelDateKey, BookingID) - still unique, since
every booking has exactly one travel date.

Run this whole script in SSMS with Query > Include Actual Execution Plan
turned on, then run the two queries at the bottom separately so each gets
its own plan.
*/

USE VayuAir;
GO

IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = 'PS_TravelDateKey')
BEGIN
    -- Nothing to drop here directly - the scheme/function are dropped
    -- further down after the table that uses them is rebuilt off them.
    PRINT 'PS_TravelDateKey already exists - will be replaced.';
END
GO

IF OBJECT_ID('dw.FactTicketSales_Partitioned', 'U') IS NOT NULL DROP TABLE dw.FactTicketSales_Partitioned;
GO

-- ----------------------------------------------------------------------------
-- Partition function + scheme. 16 boundary points -> 17 partitions total
-- (an empty one before Jan-2025, 15 real months, an empty one after Mar-2026).
-- All mapped to PRIMARY - this exercise has one filegroup; in production
-- each month (especially older, colder ones) would typically map to its
-- own filegroup for independent backup/compression/archival.
-- ----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = 'PF_TravelDateKey')
BEGIN
    DROP PARTITION SCHEME PS_TravelDateKey;
    DROP PARTITION FUNCTION PF_TravelDateKey;
END
GO

CREATE PARTITION FUNCTION PF_TravelDateKey (INT)
    AS RANGE RIGHT FOR VALUES (
        20250101, 20250201, 20250301, 20250401, 20250501, 20250601,
        20250701, 20250801, 20250901, 20251001, 20251101, 20251201,
        20260101, 20260201, 20260301, 20260401
    );
GO

CREATE PARTITION SCHEME PS_TravelDateKey
    AS PARTITION PF_TravelDateKey ALL TO ([PRIMARY]);
GO

-- ----------------------------------------------------------------------------
-- Rebuild the fact ON the partition scheme. Same columns/FKs as 02, but the
-- clustered PK is now the composite (TravelDateKey, BookingID) so the
-- table's physical layout follows the partition scheme.
-- ----------------------------------------------------------------------------
CREATE TABLE dw.FactTicketSales_Partitioned (
    BookingID        BIGINT        NOT NULL,
    BookingDateKey    INT          NOT NULL,
    TravelDateKey     INT          NOT NULL,
    PassengerKey      INT          NOT NULL,
    FlightKey         INT          NOT NULL,
    FareClass         VARCHAR(20)  NOT NULL,
    BookingStatus     VARCHAR(20)  NOT NULL,
    FareAmount        DECIMAL(18,2) NOT NULL,
    TaxAmount         DECIMAL(18,2) NOT NULL,
    MilesEarned       INT          NOT NULL,
    CONSTRAINT PK_FactTicketSales_Partitioned PRIMARY KEY CLUSTERED (TravelDateKey, BookingID)
) ON PS_TravelDateKey (TravelDateKey);
GO

INSERT INTO dw.FactTicketSales_Partitioned (
    BookingID, BookingDateKey, TravelDateKey, PassengerKey, FlightKey,
    FareClass, BookingStatus, FareAmount, TaxAmount, MilesEarned
)
SELECT
    BookingID, BookingDateKey, TravelDateKey, PassengerKey, FlightKey,
    FareClass, BookingStatus, FareAmount, TaxAmount, MilesEarned
FROM dw.FactTicketSales;
GO

DROP TABLE dw.FactTicketSales;
EXEC sp_rename 'dw.FactTicketSales_Partitioned', 'FactTicketSales';
EXEC sp_rename 'dw.PK_FactTicketSales_Partitioned', 'PK_FactTicketSales', 'OBJECT';
GO

ALTER TABLE dw.FactTicketSales ADD
    CONSTRAINT FK_Fact_BookingDate FOREIGN KEY (BookingDateKey) REFERENCES dw.DimDate (DateKey),
    CONSTRAINT FK_Fact_TravelDate  FOREIGN KEY (TravelDateKey)  REFERENCES dw.DimDate (DateKey),
    CONSTRAINT FK_Fact_Passenger   FOREIGN KEY (PassengerKey)   REFERENCES dw.DimPassenger (PassengerKey),
    CONSTRAINT FK_Fact_Flight      FOREIGN KEY (FlightKey)      REFERENCES dw.DimFlight (FlightKey);
GO

-- ----------------------------------------------------------------------------
-- Confirm the table actually sits on the scheme, and see row counts per
-- partition (a quick, non-graphical sanity check before looking at plans).
-- ----------------------------------------------------------------------------
SELECT
    p.partition_number,
    prv.value AS upper_boundary_travel_date_key,
    p.rows
FROM sys.partitions p
JOIN sys.indexes i ON i.object_id = p.object_id AND i.index_id = p.index_id
LEFT JOIN sys.partition_range_values prv
    ON prv.function_id = (SELECT function_id FROM sys.partition_functions WHERE name = 'PF_TravelDateKey')
   AND prv.boundary_id = p.partition_number
WHERE i.object_id = OBJECT_ID('dw.FactTicketSales') AND i.index_id = 1
ORDER BY p.partition_number;

-- ----------------------------------------------------------------------------
-- Query A: filters on the partition key (TravelDateKey). Run this alone
-- with "Include Actual Execution Plan" on, then check the clustered index
-- seek/scan operator's Properties pane for "Actual Partition Count" - it
-- should read 1 (June 2025 only).
--
-- OPTION (RECOMPILE) matters here. Without it, SQL Server's simple
-- parameterization silently swaps the literal boundary values for
-- parameters (the plan shows [TravelDateKey]>=@1 AND [TravelDateKey]<@2
-- instead of the literals), so the same cached plan could be reused later
-- for a different date range. But once the boundaries are unknown
-- parameters instead of literals, the optimizer can't be certain at
-- compile time exactly where @2 falls relative to a partition boundary,
-- so it conservatively touches the adjacent partition too - Actual
-- Partition Count comes back as 2 (partitions 7-8) instead of the true 1
-- (partition 7 only). RECOMPILE forces the plan to be built against the
-- actual literal values, which lets partition elimination be exact.
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS bookings, SUM(FareAmount) AS total_fare
FROM dw.FactTicketSales
WHERE TravelDateKey >= 20250601 AND TravelDateKey < 20250701
OPTION (RECOMPILE);

-- ----------------------------------------------------------------------------
-- Query B: filters on a non-partition column (BookingStatus/FareClass).
-- Same check - "Actual Partition Count" should read all 17 partitions,
-- because nothing in the predicate lets the optimizer rule any of them out.
-- ----------------------------------------------------------------------------
SELECT COUNT(*) AS bookings, SUM(FareAmount) AS total_fare
FROM dw.FactTicketSales
WHERE BookingStatus = 'Confirmed' AND FareClass = 'Business';

/*
Why: partition elimination only works when the predicate is expressed
directly on the partitioning column (or a SARGable range on it, as in
Query A) - the optimizer can map that range straight to the one or two
partitions that could hold matching rows and skip reading the rest
entirely, before execution even starts. BookingStatus and FareClass are
ordinary row-level columns with no relationship to how the table is
physically split, so a filter on them gives the optimizer nothing to prune
with - it has no choice but to touch every partition and evaluate the
filter row by row inside each one.
*/
