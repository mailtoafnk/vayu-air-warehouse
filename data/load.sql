-- DDL + load for dialect: sqlserver

CREATE TABLE bronze_airports (
  airport_code NVARCHAR(255),
  airport_name NVARCHAR(255),
  city NVARCHAR(255),
  country NVARCHAR(255),
  region NVARCHAR(255)
);
BULK INSERT bronze_airports FROM 'C:\\cb_data\\bronze_airports.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_aircraft (
  aircraft_code NVARCHAR(255),
  model NVARCHAR(255),
  manufacturer NVARCHAR(255),
  seat_capacity BIGINT
);
BULK INSERT bronze_aircraft FROM 'C:\\cb_data\\bronze_aircraft.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_passengers (
  passenger_id BIGINT,
  passenger_name NVARCHAR(255),
  home_airport_code NVARCHAR(255),
  frequent_flyer_tier NVARCHAR(255),
  signup_date DATE
);
BULK INSERT bronze_passengers FROM 'C:\\cb_data\\bronze_passengers.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE bronze_flights (
  flight_id BIGINT,
  flight_number NVARCHAR(255),
  origin_airport_code NVARCHAR(255),
  dest_airport_code NVARCHAR(255),
  aircraft_code NVARCHAR(255),
  flight_date DATE
);
BULK INSERT bronze_flights FROM 'C:\\cb_data\\bronze_flights.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

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
BULK INSERT bronze_bookings FROM 'C:\\cb_data\\bronze_bookings.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

CREATE TABLE stg_passenger_updates (
  passenger_id BIGINT,
  passenger_name NVARCHAR(255),
  home_airport_code NVARCHAR(255),
  frequent_flyer_tier NVARCHAR(255)
);
BULK INSERT stg_passenger_updates FROM 'C:\\cb_data\\stg_passenger_updates.csv' WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
