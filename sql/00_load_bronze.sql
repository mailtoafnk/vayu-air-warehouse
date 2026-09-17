/*
================================================================================
 00 - Load bronze layer
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Creates the VayuAir database and the six bronze/staging tables, then loads
them from the CSVs in data/ using BULK INSERT.

BULK INSERT reads from the SQL Server *service account's* filesystem. Paths
below point at this repo's own data/ folder
(C:\Users\meeta\Downloads\vayu-air-warehouse\data\) - edit them if you copy
the CSVs somewhere else. If the service account can't read that folder,
use the SSMS "Import Flat File" wizard instead (Tasks -> Import Flat
File...) - see docs in 03_How_to_Import_Data.pdf from the original
assignment pack.

This is the assignment's own load.sql, with paths repointed at data/ and
CREATE DATABASE plus the row-count check added.
*/

IF DB_ID('VayuAir') IS NULL
BEGIN
    CREATE DATABASE VayuAir;
END
GO

USE VayuAir;
GO

-- Drop and recreate bronze tables so this script is safely re-runnable.
IF OBJECT_ID('dbo.bronze_airports', 'U') IS NOT NULL DROP TABLE dbo.bronze_airports;
IF OBJECT_ID('dbo.bronze_aircraft', 'U') IS NOT NULL DROP TABLE dbo.bronze_aircraft;
IF OBJECT_ID('dbo.bronze_passengers', 'U') IS NOT NULL DROP TABLE dbo.bronze_passengers;
IF OBJECT_ID('dbo.bronze_flights', 'U') IS NOT NULL DROP TABLE dbo.bronze_flights;
IF OBJECT_ID('dbo.bronze_bookings', 'U') IS NOT NULL DROP TABLE dbo.bronze_bookings;
IF OBJECT_ID('dbo.stg_passenger_updates', 'U') IS NOT NULL DROP TABLE dbo.stg_passenger_updates;
GO

CREATE TABLE bronze_airports (
  airport_code NVARCHAR(255),
  airport_name NVARCHAR(255),
  city NVARCHAR(255),
  country NVARCHAR(255),
  region NVARCHAR(255)
);
BULK INSERT bronze_airports FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\bronze_airports.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_aircraft (
  aircraft_code NVARCHAR(255),
  model NVARCHAR(255),
  manufacturer NVARCHAR(255),
  seat_capacity BIGINT
);
BULK INSERT bronze_aircraft FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\bronze_aircraft.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_passengers (
  passenger_id BIGINT,
  passenger_name NVARCHAR(255),
  home_airport_code NVARCHAR(255),
  frequent_flyer_tier NVARCHAR(255),
  signup_date DATE
);
BULK INSERT bronze_passengers FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\bronze_passengers.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_flights (
  flight_id BIGINT,
  flight_number NVARCHAR(255),
  origin_airport_code NVARCHAR(255),
  dest_airport_code NVARCHAR(255),
  aircraft_code NVARCHAR(255),
  flight_date DATE
);
BULK INSERT bronze_flights FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\bronze_flights.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_bookings (
  booking_id BIGINT,
  passenger_id BIGINT,
  flight_id BIGINT,
  booking_date DATE,
  travel_date DATE,
  fare_class NVARCHAR(255),
  fare_amount DECIMAL(18,2),
  tax_amount DECIMAL(18,2),
  booking_status NVARCHAR(255),
  miles_earned BIGINT
);
BULK INSERT bronze_bookings FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\bronze_bookings.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE stg_passenger_updates (
  passenger_id BIGINT,
  passenger_name NVARCHAR(255),
  home_airport_code NVARCHAR(255),
  frequent_flyer_tier NVARCHAR(255)
);
BULK INSERT stg_passenger_updates FROM 'C:\Users\meeta\Downloads\vayu-air-warehouse\data\stg_passenger_updates.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

-- Confirm the load. Expected: 24 / 10 / 1,500 / 2,000 / 40,000 / 250.
SELECT 'bronze_airports' AS table_name, COUNT(*) AS row_count FROM bronze_airports
UNION ALL SELECT 'bronze_aircraft', COUNT(*) FROM bronze_aircraft
UNION ALL SELECT 'bronze_passengers', COUNT(*) FROM bronze_passengers
UNION ALL SELECT 'bronze_flights', COUNT(*) FROM bronze_flights
UNION ALL SELECT 'bronze_bookings', COUNT(*) FROM bronze_bookings
UNION ALL SELECT 'stg_passenger_updates', COUNT(*) FROM stg_passenger_updates;
GO
