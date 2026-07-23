use rusqlite::{params, Connection, OptionalExtension};

use crate::error::{RuntimeError, RuntimeResult};

pub const LOCAL_CHANGE_SEQ_KEY: &str = "local_change_seq";

/// Create the runtime tables that production migrations also create.
///
/// Production code does NOT need this — schema migrations in `lorvex-store`
/// create these tables. This exists only for lorvex-runtime's own tests
/// (and downstream `test-support` consumers) which use raw
/// `Connection::open_in_memory()` without the full migration stack.
///
/// the shape MUST mirror
/// `lorvex-store/src/schema/001_schema.sql` for `local_sync_owner`,
/// `local_counters`, and `mcp_host_authority`. A dedicated parity test
/// (see [`tests::runtime_fixture_matches_production_schema`]) runs the
/// production migration stack against an in-memory DB and asserts the
/// column shapes match this fixture, so drift between the two surfaces
/// is caught at test time rather than on a customer device.
#[cfg(any(test, feature = "test-support"))]
pub fn initialize_local_runtime_tables(conn: &Connection) -> RuntimeResult<()> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS local_sync_owner (
            lease_name TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            expires_at_epoch_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE IF NOT EXISTS local_counters (
            name TEXT PRIMARY KEY,
            value INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        ) STRICT;

        CREATE TABLE IF NOT EXISTS mcp_host_authority (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            host TEXT NOT NULL CHECK (host IN ('app', 'cli')),
            priority INTEGER NOT NULL,
            host_path TEXT,
            updated_at INTEGER NOT NULL
        ) STRICT;",
    )?;
    Ok(())
}

/// Read the current `local_change_seq` counter.
///
/// The counter lives in the `local_counters` table as an `INTEGER NOT
/// NULL` `value` column keyed by name. A missing row reads as `0`; a
/// negative stored value is treated as corruption and surfaced as
/// `RuntimeError::CorruptLocalChangeSeq` rather than silently
/// resetting. The bump path (`value = value + 1`) uses matching
/// integer bind types end-to-end so a bad input cannot truncate the
/// counter back to zero.
pub fn read_local_change_seq(conn: &Connection) -> RuntimeResult<u64> {
    let value: Option<i64> = conn
        .query_row(
            "SELECT value FROM local_counters WHERE name = ?1",
            [LOCAL_CHANGE_SEQ_KEY],
            |row| row.get(0),
        )
        .optional()?;

    match value {
        None => Ok(0),
        Some(v) if v < 0 => Err(RuntimeError::CorruptLocalChangeSeq {
            value: v.to_string(),
        }),
        Some(v) => Ok(v as u64),
    }
}

/// Atomically increment `local_change_seq` and return the post-increment
/// value.
///
/// The bump is a single
/// `INSERT ... ON CONFLICT DO UPDATE SET value = value + 1 RETURNING value`
/// against an INTEGER column. A TEXT column with
/// `CAST(CAST(value AS INTEGER) + 1 AS TEXT)` would silently
/// truncate on overflow and silently reset to 0 on any non-numeric
/// payload — both failure modes break the monotonicity invariant
/// that every consumer of the change-seq depends on.
pub fn bump_local_change_seq(conn: &Connection) -> RuntimeResult<u64> {
    let updated_at = current_timestamp_ms();
    let next: i64 = conn.query_row(
        "INSERT INTO local_counters (name, value, updated_at) VALUES (?1, 1, ?2)
         ON CONFLICT(name) DO UPDATE SET
           value = local_counters.value + 1,
           updated_at = excluded.updated_at
         RETURNING value",
        params![LOCAL_CHANGE_SEQ_KEY, updated_at],
        |row| row.get(0),
    )?;
    if next < 0 {
        return Err(RuntimeError::CorruptLocalChangeSeq {
            value: next.to_string(),
        });
    }
    Ok(next as u64)
}

/// Wall-clock epoch milliseconds, clamped to `i64::MAX` on overflow
/// (year 2262 — well past anything Lorvex needs to support).
///
/// **Use this only for `updated_at`-shaped audit columns where any
/// monotonic value satisfies the contract.** Lease/timeout math must
/// route through [`current_timestamp_ms_for_lease`] so that an
/// overflow surfaces as a typed error instead of silently producing
/// `i64::MAX`, which the strict-less-than steal predicate
/// (`expires_at_epoch_ms < ?4`) can never beat — pinning the lease
/// forever.
///
/// Returns `i64` rather than `u128` so callers can bind it directly to
/// SQLite `INTEGER` columns (`local_sync_owner.updated_at`,
/// `local_counters.updated_at`, `mcp_host_authority.updated_at`). The
/// previous TEXT shape silently lex-compared digit strings; the
/// integer shape compares numerically.
///
/// On a freshly provisioned VM or a device with a missing RTC battery
/// where the clock reads before 1970, `.expect(..)` would panic the
/// whole process on the very first local write, wedging the user's
/// data flow. `bump_local_change_seq` fires on every mutation; this
/// cannot be the failure mode. Monotonicity isn't required here — the
/// value only feeds a SQLite `updated_at` reconciled elsewhere — so
/// zero is strictly safe.
pub(crate) fn current_timestamp_ms() -> i64 {
    let raw = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or(std::time::Duration::ZERO)
        .as_millis();
    i64::try_from(raw).unwrap_or(i64::MAX)
}

/// Wall-clock epoch milliseconds for lease-expiry math, returning
/// `RuntimeError::SystemClockOutOfRange` on overflow rather than
/// saturating to `i64::MAX`.
///
/// `try_acquire_sync_owner_now` and `renew_sync_owner_now` route
/// through this so a year-2262+ clock or a corrupted system clock
/// cannot mint a lease whose `expires_at_epoch_ms` saturates to
/// `i64::MAX` — a value the strict-less-than steal predicate
/// (`expires_at_epoch_ms < ?4`) can never beat. The previous shape
/// silently saturated and pinned the row forever.
pub(crate) fn current_timestamp_ms_for_lease() -> crate::RuntimeResult<i64> {
    let raw = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or(std::time::Duration::ZERO)
        .as_millis();
    i64::try_from(raw).map_err(|_| crate::RuntimeError::SystemClockOutOfRange)
}

#[cfg(test)]
mod tests;
