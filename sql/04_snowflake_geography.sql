/*
================================================================================
 04 - Snowflake the geography (Build, Q4)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Normalises dw.DimAirport's denormalised city/country/region columns into
three linked tables: DimCountry -> DimCity -> DimAirport.

Loaded bottom-up (country, then city, then airport-level FK) so every
foreign key resolves on first insert, per the hint. Existing AirportKey
values are preserved - this ALTERs DimAirport in place rather than
rebuilding it, so DimFlight, DimPassenger and FactTicketSales (already
loaded in 03) don't need to be touched.

In this dataset each country maps to exactly one region (India -> South
Asia, UAE -> Middle East, etc.), so Region is modelled as an attribute of
DimCountry, not of DimAirport.
*/

USE VayuAir;
GO

IF OBJECT_ID('dw.DimCity', 'U') IS NOT NULL DROP TABLE dw.DimCity;
IF OBJECT_ID('dw.DimCountry', 'U') IS NOT NULL DROP TABLE dw.DimCountry;
GO

-- ----------------------------------------------------------------------------
-- DimCountry
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimCountry (
    CountryKey    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CountryName   VARCHAR(100) NOT NULL,
    Region        VARCHAR(50)  NOT NULL,
    CONSTRAINT UQ_DimCountry_Name UNIQUE (CountryName)
);
GO

INSERT INTO dw.DimCountry (CountryName, Region)
SELECT DISTINCT Country, Region
FROM dw.DimAirport;
GO

-- ----------------------------------------------------------------------------
-- DimCity - unique per (CityName, CountryKey): city names alone are not
-- guaranteed globally unique (e.g. a "Paris, Texas" could exist alongside
-- "Paris, France" in a bigger network), so the natural key is the pair.
-- ----------------------------------------------------------------------------
CREATE TABLE dw.DimCity (
    CityKey       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CityName      VARCHAR(100) NOT NULL,
    CountryKey    INT          NOT NULL,
    CONSTRAINT UQ_DimCity_Name_Country UNIQUE (CityName, CountryKey),
    CONSTRAINT FK_DimCity_Country FOREIGN KEY (CountryKey) REFERENCES dw.DimCountry (CountryKey)
);
GO

INSERT INTO dw.DimCity (CityName, CountryKey)
SELECT DISTINCT a.City, c.CountryKey
FROM dw.DimAirport a
JOIN dw.DimCountry c ON c.CountryName = a.Country;
GO

-- ----------------------------------------------------------------------------
-- DimAirport: add CityKey, backfill it, then drop the denormalised columns.
-- ----------------------------------------------------------------------------
ALTER TABLE dw.DimAirport ADD CityKey INT NULL;
GO

UPDATE a
SET a.CityKey = ci.CityKey
FROM dw.DimAirport a
JOIN dw.DimCountry co ON co.CountryName = a.Country
JOIN dw.DimCity    ci ON ci.CityName = a.City AND ci.CountryKey = co.CountryKey;
GO

ALTER TABLE dw.DimAirport ALTER COLUMN CityKey INT NOT NULL;
ALTER TABLE dw.DimAirport ADD CONSTRAINT FK_DimAirport_City FOREIGN KEY (CityKey) REFERENCES dw.DimCity (CityKey);
GO

ALTER TABLE dw.DimAirport DROP COLUMN City;
ALTER TABLE dw.DimAirport DROP COLUMN Country;
ALTER TABLE dw.DimAirport DROP COLUMN Region;
GO

-- ----------------------------------------------------------------------------
-- Acceptance check: resolve an airport all the way up to its country.
-- ----------------------------------------------------------------------------
SELECT
    a.AirportCode,
    a.AirportName,
    ci.CityName,
    co.CountryName,
    co.Region
FROM dw.DimAirport a
JOIN dw.DimCity    ci ON ci.CityKey    = a.CityKey
JOIN dw.DimCountry co ON co.CountryKey = ci.CountryKey
ORDER BY co.CountryName, ci.CityName, a.AirportCode;

/*
Trade-off: snowflaking removes the repeated city/country/region text that
sat on every one of the 24 airport rows (and would keep repeating on every
new airport added), and it makes country-level facts like Region
consistent by construction instead of by discipline - but every query that
wants an airport's country now has to walk two extra joins instead of
reading one flat row, and DimAirport is no longer independently readable
without joining out to DimCity/DimCountry.
*/
