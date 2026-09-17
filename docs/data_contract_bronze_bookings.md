# Data Contract — `bronze_bookings`

Vayu Air · Session 3, Q7(b)

## Owner

**Booking Systems team** (source system of record). Analytics engineering (this
pipeline's maintainer) is the consumer, not the owner — schema changes are
proposed and approved by Booking Systems, communicated to consumers before
they ship.

## Schema and types

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `booking_id` | `BIGINT` | No | Unique per row. Primary key of the feed. |
| `passenger_id` | `BIGINT` | No | Must exist in `bronze_passengers` at time of delivery. |
| `flight_id` | `BIGINT` | No | Must exist in `bronze_flights` at time of delivery. |
| `booking_date` | `DATE` | No | Date the ticket was booked. `booking_date <= travel_date`. |
| `travel_date` | `DATE` | No | Date of the flight travelled; equals the referenced flight's `flight_date`. |
| `fare_class` | `NVARCHAR(255)` | No | One of the allowed values below. |
| `fare_amount` | `DECIMAL(18,2)` | No | Base fare in INR. `>= 0`. |
| `tax_amount` | `DECIMAL(18,2)` | No | Taxes and fees in INR. `>= 0`. |
| `booking_status` | `NVARCHAR(255)` | No | One of the allowed values below. |
| `miles_earned` | `BIGINT` | No | Loyalty miles credited. `>= 0`. |

## Allowed values

- `fare_class`: `Economy`, `Premium Economy`, `Business`, `First`
- `booking_status`: `Confirmed`, `Cancelled`, `NoShow`

Any other value is a contract violation, not a new category to silently
accept — the pipeline should reject or quarantine the batch and alert the
owner rather than load it.

## Freshness / delivery SLA

- Delivered once daily as a full snapshot file, landed by **06:00 IST**.
- Downstream gold-layer refresh depends on same-day delivery; a file that
  hasn't landed by 08:00 IST triggers a freshness alert to the owner and
  pauses the day's warehouse refresh rather than running on stale data.
- Row count is expected to be non-decreasing day over day (bookings are
  never physically deleted from the source, only status-changed); a
  same-day row count drop of more than 1% versus the prior file also
  triggers an alert.

## Breaking vs. non-breaking change — one example each

- **Non-breaking**: adding a new optional column, e.g. `payment_method`,
  appended at the end of the schema with a default/nullable value.
  Existing consumers that select named columns (not `SELECT *`) are
  unaffected; new consumers can opt in.
- **Breaking**: renaming `booking_status` to `status`, removing a column,
  changing a column's type (e.g. `fare_amount` from `DECIMAL(18,2)` to
  `FLOAT`), or adding a new allowed value to `booking_status` without
  notice (e.g. `Refunded`) — the last one is breaking even though it looks
  additive, because every downstream `CASE`/filter written against the
  three known statuses (this pipeline's revenue queries included) would
  silently miscount the new status as neither confirmed nor excluded.

Any breaking change requires advance notice to the owner list and a
version bump on the feed; non-breaking changes can ship without notice but
should still be announced.
