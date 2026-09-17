# Vayu Air Warehouse — Session 3: Data Modeling & Warehouse Engineering

**Live walkthrough:** [mailtoafnk.github.io/vayu-air-warehouse](https://mailtoafnk.github.io/vayu-air-warehouse/)
— a guided, question-by-question tour of Q1–Q7 (grain, star schema, SCD2,
partitioning, medallion mapping) with the real verification numbers from the
live database. The scripts and write-up below are the full detail behind it.

Codebasics Data Engineering Bootcamp. Engine: SQL Server (T-SQL), run in SSMS
on the `VayuAir` database.

## Repo structure

```
data/
  bronze_airports.csv, bronze_aircraft.csv, bronze_passengers.csv,
  bronze_flights.csv, bronze_bookings.csv, stg_passenger_updates.csv
  load.sql              <- original assignment loader, for reference
sql/
  00_load_bronze.sql                  <- creates VayuAir + loads the 6 bronze/staging tables
  01_grain_and_classification.sql     <- Q1: grain statement, dimension-key/measure split (comments only)
  02_star_schema_ddl.sql              <- Q2: dw schema, star schema DDL
  03_load_dimensions_and_fact.sql     <- Q3: populate dimensions + FactTicketSales
  04_snowflake_geography.sql          <- Q4: DimAirport -> DimCity -> DimCountry
  05_scd2_passenger_dimension.sql     <- Q5: SCD2 rebuild + stg_passenger_updates apply
  06_partition_fact_ticket_sales.sql  <- Q6: partition function/scheme + pruning proof
docs/
  data_contract_bronze_bookings.md    <- Q7(b): data contract
screenshots/
  q6_partition_key_query_plan.png     <- Query A execution plan (Actual Partition Count)
  q6_non_partition_query_plan.png     <- Query B execution plan (Actual Partition Count)
README.md   <- this file (design write-up + Q7(a) medallion mapping)
index.html  <- the live walkthrough page above, served via GitHub Pages
```

Run the `sql/` scripts in numeric order against a fresh `VayuAir` database.
Each file is self-contained and re-runnable from a clean state.

**Before running 00**: `BULK INSERT` reads from the SQL Server *service
account's* filesystem, so the CSVs need to live somewhere that account can
read. `sql/00_load_bronze.sql`'s `BULK INSERT` paths already point at this
repo's own `data/` folder — if you clone this repo to a different location,
update those paths to match. If the service account can't be granted access
to that folder at all, use SSMS's Import Flat File wizard instead (Tasks ->
Import Flat File...) and skip straight to `01`.

## Design write-up

### Grain (Q1)

> One row in `FactTicketSales` = one ticket sold: a single `booking_id`
> (one passenger's seat on one flight).

`bronze_bookings` is already at this grain — `booking_id` is unique across
all 40,000 rows — so the fact is a straight, dimensionalized copy of
`bronze_bookings`, not a roll-up or a fan-out. Full column-by-column
classification (dimension key vs. measure, additive vs. non-additive) is in
`sql/01_grain_and_classification.sql`.

### Star schema (Q2/Q3)

`DimDate` (yyyymmdd surrogate = business key, deliberately — no lookup
needed to build it), `DimAirport`, `DimAircraft`, `DimPassenger` and
`DimFlight` all get `IDENTITY` surrogate keys with their source column kept
as a unique business key. `FactTicketSales` holds two role-playing FKs to
`DimDate` — `BookingDateKey` and `TravelDateKey` — since a sales fact for an
airline genuinely has two dates that matter (when it was booked, when it
was flown), and one conformed date dimension serves both rather than
building two near-identical tables.

`fare_class` and `booking_status` stay as plain attributes directly on the
fact rather than becoming their own dimensions: each has only 3–4 fixed
values and no attributes of its own, so a junk/mini-dimension would add a
join for no descriptive gain. `BookingID` doubles as the fact's own primary
key rather than adding a surrogate on top of it, since the grain is
1:1 with bookings already.

Load order in `03` respects the FK graph: `DimDate` and the "leaf"
dimensions first, `DimFlight` after `DimAirport`/`DimAircraft` (it FKs to
both), then the fact last. All four dimension FKs on the fact are inner
joins on purpose — the data dictionary and a direct check against the
actual CSVs confirm every `passenger_id`, `flight_id`, `origin/dest
_airport_code` and `aircraft_code` in the bronze tables always resolves, so
an inner join that silently dropped rows here would itself be a signal
worth investigating, not something to paper over with a `LEFT JOIN`.

### Snowflaked geography (Q4)

`DimAirport`'s `city`/`country`/`region` columns split into `DimCountry` →
`DimCity` → `DimAirport`, loaded bottom-up so every FK resolves on first
insert. `Region` lives on `DimCountry`, not `DimAirport`: checking the
actual 24-row airport table shows every country maps to exactly one region
(India → South Asia, UAE → Middle East, and so on), so region is a
country-level attribute, not an airport-level one.

The rebuild is done as an in-place `ALTER` (add `CityKey`, backfill, drop
the flat columns) rather than a drop-and-recreate, specifically so
`DimAirport`'s existing `AirportKey` values — already referenced by
`DimFlight` and `DimPassenger` from the Q3 load — never change and nothing
downstream needs reloading.

**Trade-off**: normalizing removes the repeated city/country/region text
that sat on every airport row (and would keep repeating on every airport
added later), and makes country-level facts consistent by construction —
at the cost of two extra joins for any query that wants an airport's
country, where before it was one flat row.

### SCD2 passenger dimension (Q5)

Same in-place-`ALTER` philosophy as Q4: `IsCurrent`, `EffectiveFrom`,
`EffectiveTo` are added to the existing `DimPassenger` rather than dropping
and rebuilding it, because `FactTicketSales` already holds `PassengerKey`
values from the Q3 load and those must stay valid.

The two-pass pattern:

1. **`MERGE`** — for existing passengers whose current row has a different
   `frequent_flyer_tier` or `HomeAirportKey` than the feed, expire it
   (`IsCurrent = 0`, `EffectiveTo = @AsOf`); for `passenger_id`s not yet in
   the dimension at all, insert them as a brand-new current row in the same
   statement.
2. **A separate `INSERT`** — opens the new current version for every row
   just expired in step 1.

Checked against the actual `stg_passenger_updates.csv` before writing this:
all 200 rows that match an existing passenger carry a genuine change (191
tier changes, 91 home-airport changes, overlapping on some rows), and the
other 50 rows (`passenger_id` 900000–900049) are brand-new — so both
branches of the `MERGE` get exercised for real, not just in theory. Net
effect: 1,500 → 1,750 total rows, 1,500 → 1,550 current rows.

One nuance worth being explicit about: the fact was loaded in Q3, *before*
this SCD2 rebuild, against whichever passenger row was current at the
time. That's fine for this one-time historical build, since every one of
the 40,000 bookings predates every change in the feed — but it's exactly
why `EffectiveFrom`/`EffectiveTo` exist rather than just an `IsCurrent`
flag: a real incremental pipeline should resolve new fact rows with an
as-of join (`booking_date` between a passenger version's effective dates),
not always against `IsCurrent = 1`, so a booking always points at the
passenger attributes that were actually true when it happened. This is
spelled out with the exact join shape in a comment at the bottom of
`sql/05_scd2_passenger_dimension.sql`.

### Partitioning (Q6)

Partitioned on `TravelDateKey` (not `BookingDateKey`) — the date a
passenger actually flew is the natural axis for an airline's "sales by
travel period" reporting, which is where a fact this size gets scanned
over and over. Monthly `RANGE RIGHT` boundaries span exactly the data's
`travel_date` range (Jan 2025–Mar 2026, from `sql/06`'s own boundary list):
16 boundary values give 17 partitions — one real partition per month
(15 months of actual data) plus an empty catch-all on each end.

SQL Server requires the partitioning column to be part of whatever
unique/clustered index places the table on the scheme, so the fact's
clustered PK becomes the composite `(TravelDateKey, BookingID)` — still
unique, since every booking has exactly one travel date.

Two queries, one plan each (see `screenshots/`):

- **Query A** filters `WHERE TravelDateKey >= 20250601 AND TravelDateKey <
  20250701` — a SARGable range directly on the partitioning column. Actual
  Partition Count: **1**.
- **Query B** filters on `BookingStatus`/`FareClass` — ordinary row-level
  columns with no relationship to how the table is split. Actual Partition
  Count: **17** (all of them).

**Why**: partition elimination happens before execution starts, purely
from comparing the predicate to each partition's boundary values — the
optimizer can only do that when the predicate is expressed on the
partitioning column itself (or a range on it). A predicate on any other
column gives it nothing to compare against partition boundaries with, so
every partition has to be opened and scanned row-by-row to evaluate the
filter.

**A wrinkle worth documenting**: run Query A exactly as written above and
the plan actually reports Actual Partition Count = **2** (partitions 7-8),
not 1. That's because SQL Server's simple parameterization rewrites the
literal boundaries into parameters behind the scenes (the plan shows
`[TravelDateKey]>=@1 AND [TravelDateKey]<@2`), so it can potentially reuse
that cached plan for a different date range later. Once the boundaries are
unknown parameters rather than literals, the optimizer can't be certain at
compile time exactly where `@2` falls relative to a partition boundary, so
it conservatively includes the adjacent partition too. Adding
`OPTION (RECOMPILE)` to Query A forces the plan to compile against the
actual literal values, which restores exact elimination — Actual Partition
Count = **1**, Actual Partitions Accessed = `7`. `sql/06` includes this
hint on Query A for that reason.

### Medallion mapping (Q7a)

| Table | Layer | Why |
|---|---|---|
| `bronze_airports`, `bronze_aircraft`, `bronze_passengers`, `bronze_flights`, `bronze_bookings`, `stg_passenger_updates` | **Bronze** | Raw, source-shaped, unconformed — landed as-is from the booking system, exactly the shape/types the source produces. |
| `dw.DimPassenger` (SCD2) | **Silver** | Cleaned and conformed: business key stabilized, history tracked, home airport resolved to a real FK instead of a loose code. Not yet the star used by dashboards. |
| `dw.DimAirport` / `dw.DimCity` / `dw.DimCountry` | **Silver** | Same reasoning — conformed, normalized, FK-linked geography built from the raw flat columns. |
| `dw.DimDate`, `dw.DimAircraft`, `dw.DimFlight` | **Silver** | Conformed dimensions with surrogate keys and validated business keys, built for reuse across facts. |
| `dw.FactTicketSales` (partitioned) | **Gold** | The curated, partitioned star — additive measures only, fully resolved FKs, sized and physically laid out for the queries dashboards actually run. |

### Data contract (Q7b)

See `docs/data_contract_bronze_bookings.md` for the full contract on the
`bronze_bookings` feed: schema and types, allowed values for `fare_class`
and `booking_status`, freshness/delivery SLA, ownership, and one breaking
and one non-breaking change example.

## Grading self-check

- **Correctness**: every script's acceptance-criteria queries (row counts,
  orphan-FK checks, current-version counts, partition counts) were run
  against the actual loaded data, not assumed from the data dictionary
  alone — referential integrity across all six bronze tables and the exact
  shape of `stg_passenger_updates` (200 real changes, 50 real inserts) were
  checked directly against the CSVs before any DDL was written.
- **Logic & approach**: grain declared before any table; surrogate keys
  with business keys preserved throughout; star vs. snowflake applied
  exactly where the assignment asks (flat first, snowflaked in Q4); SCD2
  via the two-pass expire-then-insert pattern, done as in-place `ALTER`s
  so downstream FKs never break; partitioning aligned to the column the
  business actually filters by.
- **Readability**: every script commented with the grain, the reasoning
  behind non-obvious choices (role-playing date dimension, region on
  country not airport, in-place rebuilds over drop-and-recreate), and the
  acceptance-criteria checks inline as runnable queries.
- **Communication**: this write-up, plus the per-file header comments and
  the standalone data contract doc.
