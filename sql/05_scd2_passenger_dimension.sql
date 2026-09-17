/*
================================================================================
 05 - SCD Type 2 passenger dimension (Build, Q5)
 Vayu Air | Session 3: Data Modeling & Warehouse Engineering
================================================================================
Rebuilds dw.DimPassenger to carry history: a new surrogate key per version,
the stable business key (PassengerID), is_current, effective_from,
effective_to. Then applies stg_passenger_updates using the two-pass
expire-then-insert pattern:

  Pass 1 (MERGE): for passengers already in the dimension, expire the
  current version when tier or home airport actually changed; for
  passenger_ids not yet in the dimension, insert them as a brand-new
  current row in the same statement.

  Pass 2 (separate INSERT): add the new current version for every
  passenger just expired in pass 1.

This ALTERs the existing DimPassenger in place (adds the tracking columns)
rather than dropping and recreating it, the same way 04 altered DimAirport
in place - FactTicketSales (loaded in 03) already holds PassengerKey values
from this table, and PassengerKey never changes for an existing version, so
the fact's foreign keys stay valid throughout.

All 200 "existing" rows in stg_passenger_updates carry a genuine change
(191 tier changes, 91 home-airport changes, some both) and the other 50 are
brand-new passenger_ids (900000-900049) - verified against the actual data,
not assumed - so this script's branches all get exercised on this feed.
*/

USE VayuAir;
GO

-- ----------------------------------------------------------------------------
-- Add SCD2 tracking columns to the existing dimension, backfilling every
-- current row as "version 1, current since its own signup_date".
-- ----------------------------------------------------------------------------
ALTER TABLE dw.DimPassenger ADD
    IsCurrent      BIT  NULL,
    EffectiveFrom  DATE NULL,
    EffectiveTo    DATE NULL;
GO

UPDATE dw.DimPassenger
SET IsCurrent = 1,
    EffectiveFrom = SignupDate,
    EffectiveTo = '9999-12-31';
GO

ALTER TABLE dw.DimPassenger ALTER COLUMN IsCurrent     BIT  NOT NULL;
ALTER TABLE dw.DimPassenger ALTER COLUMN EffectiveFrom DATE NOT NULL;
ALTER TABLE dw.DimPassenger ALTER COLUMN EffectiveTo   DATE NOT NULL;
GO

-- PassengerID is no longer unique on its own (a changed passenger will have
-- two rows) - replace the plain unique constraint with one scoped to the
-- current version, so lookups from the fact stay a simple equality join.
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_DimPassenger_PassengerID')
    ALTER TABLE dw.DimPassenger DROP CONSTRAINT UQ_DimPassenger_PassengerID;
GO

CREATE UNIQUE INDEX UQ_DimPassenger_CurrentVersion
    ON dw.DimPassenger (PassengerID)
    WHERE IsCurrent = 1;
GO

-- ----------------------------------------------------------------------------
-- Apply the daily change feed. @AsOf is "today" for this feed - the day
-- these changes take effect.
-- ----------------------------------------------------------------------------
DECLARE @AsOf DATE = CAST(GETDATE() AS DATE);

-- Pass 1: expire changed current versions; insert brand-new passengers.
MERGE dw.DimPassenger AS tgt
USING (
    SELECT
        u.passenger_id,
        u.passenger_name,
        a.AirportKey,
        u.frequent_flyer_tier
    FROM stg_passenger_updates u
    JOIN dw.DimAirport a ON a.AirportCode = u.home_airport_code
) AS src
ON tgt.PassengerID = src.passenger_id AND tgt.IsCurrent = 1
WHEN MATCHED AND (
        tgt.FrequentFlyerTier <> src.frequent_flyer_tier
     OR tgt.HomeAirportKey    <> src.AirportKey
     )
    THEN UPDATE SET IsCurrent = 0, EffectiveTo = @AsOf
WHEN NOT MATCHED BY TARGET
    THEN INSERT (PassengerID, PassengerName, HomeAirportKey, FrequentFlyerTier, SignupDate, IsCurrent, EffectiveFrom, EffectiveTo)
    VALUES (src.passenger_id, src.passenger_name, src.AirportKey, src.frequent_flyer_tier, @AsOf, 1, @AsOf, '9999-12-31');

-- Pass 2: open the new current version for everyone just expired above.
-- (Brand-new passengers were already inserted as current in pass 1, so
-- this only ever matches rows that pass 1 just set IsCurrent = 0 today.)
INSERT INTO dw.DimPassenger (PassengerID, PassengerName, HomeAirportKey, FrequentFlyerTier, SignupDate, IsCurrent, EffectiveFrom, EffectiveTo)
SELECT
    expired.PassengerID,
    src.passenger_name,
    src.AirportKey,
    src.frequent_flyer_tier,
    expired.SignupDate,
    1,
    @AsOf,
    '9999-12-31'
FROM dw.DimPassenger expired
JOIN (
    SELECT u.passenger_id, u.passenger_name, a.AirportKey, u.frequent_flyer_tier
    FROM stg_passenger_updates u
    JOIN dw.DimAirport a ON a.AirportCode = u.home_airport_code
) AS src ON src.passenger_id = expired.PassengerID
WHERE expired.IsCurrent = 0 AND expired.EffectiveTo = @AsOf;
GO

-- ----------------------------------------------------------------------------
-- Verification: acceptance criteria for Q5.
-- ----------------------------------------------------------------------------
-- Total rows: 1,500 originals + 200 reopened current versions + 50
-- brand-new passengers = 1,750; current rows = 1,500 - 200 expired + 200
-- reopened + 50 new = 1,550.
SELECT COUNT(*) AS total_rows, SUM(CAST(IsCurrent AS INT)) AS current_rows FROM dw.DimPassenger;

-- A passenger who changed: two versions, correct flags/dates.
SELECT PassengerKey, PassengerID, FrequentFlyerTier, IsCurrent, EffectiveFrom, EffectiveTo
FROM dw.DimPassenger
WHERE PassengerID = 700000  -- Kabir Sharma, tier Blue -> Silver in the feed
ORDER BY EffectiveFrom;

-- A brand-new passenger: a single current row.
SELECT PassengerKey, PassengerID, PassengerName, FrequentFlyerTier, IsCurrent, EffectiveFrom, EffectiveTo
FROM dw.DimPassenger
WHERE PassengerID = 900000;

-- Exactly one current row per PassengerID (no accidental double-current, no gaps).
SELECT PassengerID, COUNT(*) AS current_versions
FROM dw.DimPassenger
WHERE IsCurrent = 1
GROUP BY PassengerID
HAVING COUNT(*) <> 1;
-- Expect 0 rows back.

-- FactTicketSales still resolves every PassengerKey after the ALTER (proof
-- the in-place rebuild didn't orphan the fact, unlike a drop-and-recreate would).
SELECT COUNT(*) AS orphan_fact_rows
FROM dw.FactTicketSales f
WHERE NOT EXISTS (SELECT 1 FROM dw.DimPassenger p WHERE p.PassengerKey = f.PassengerKey);
-- Expect 0.

/*
Note on FactTicketSales and SCD2: 03 loaded the fact against DimPassenger
before this rebuild, joining each booking to whichever passenger row was
current at load time - those PassengerKey values are untouched by the
ALTER above, so every existing fact row still resolves correctly.

In a real incremental pipeline, new fact rows loaded *after* this SCD2
rebuild should resolve PassengerKey with an as-of join - matching the
booking's date to the passenger version whose
[EffectiveFrom, EffectiveTo) window contains it - rather than always
joining to IsCurrent = 1, so a booking always points at the passenger
attributes that were true when it happened:

  JOIN dw.DimPassenger p
    ON p.PassengerID = b.passenger_id
   AND b.booking_date >= p.EffectiveFrom
   AND b.booking_date <  p.EffectiveTo

This repo's fact load is a one-time historical build (all 40,000 bookings
predate every change in stg_passenger_updates), so it isn't required here,
but it's the reason effective_from/effective_to exist at all rather than
just an is_current flag.
*/
