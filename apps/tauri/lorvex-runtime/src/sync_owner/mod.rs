mod guard;
mod owner_id;

#[cfg(test)]
mod tests;

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::{RuntimeError, RuntimeResult};

pub use guard::{LeaseReleaseFn, ReleasePanicHook, SyncOwnerLeaseGuard};
pub use owner_id::process_owner_id;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncOwnerLease {
    pub lease_name: String,
    pub owner_id: String,
    pub expires_at_epoch_ms: i64,
}

pub fn current_sync_owner(
    conn: &Connection,
    lease_name: &str,
) -> RuntimeResult<Option<SyncOwnerLease>> {
    conn.query_row(
        "SELECT lease_name, owner_id, expires_at_epoch_ms
         FROM local_sync_owner
         WHERE lease_name = ?1",
        [lease_name],
        |row| {
            Ok(SyncOwnerLease {
                lease_name: row.get(0)?,
                owner_id: row.get(1)?,
                expires_at_epoch_ms: row.get(2)?,
            })
        },
    )
    .optional()
    .map_err(Into::into)
}

/// maximum TTL the runtime will hand out, regardless
/// of caller input. 24 hours bounds the worst case where a transport's
/// arithmetic produces a wildly inflated value (e.g. multiplying by a
/// jitter factor without saturating); a stuck lease in that range is
/// noticeable and recoverable, while one stretching to `i64::MAX` would
/// effectively pin the row forever.
pub const MAX_LEASE_TTL_MS: i64 = 86_400_000;

fn try_acquire_sync_owner(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    now_epoch_ms: i64,
    ttl_ms: i64,
) -> RuntimeResult<bool> {
    // Conditional INSERT ... ON CONFLICT DO UPDATE WHERE: acquisition succeeds
    // atomically when no live row exists OR when the existing row is either
    // owned by us or past its TTL. A prior two-step read-then-write version
    // had a cross-process TOCTOU where two surfaces could both observe "no
    // owner" and both INSERT-OR-REPLACE each other, with both believing they
    // held the lease. Pushing the liveness check into the SQL WHERE clause
    // closes that window: only one process's conditional update applies.
    //
    // a prior version coerced any non-positive TTL with
    // `.max(1)`, which silently installed a 1 ms lease when a caller's TTL
    // arithmetic underflowed (e.g. `cap_ms - elapsed_ms` going negative).
    // Reject `ttl_ms < 1` explicitly so the upstream bug surfaces.
    if ttl_ms < 1 {
        return Err(RuntimeError::InvalidLeaseTtl(ttl_ms));
    }
    // clamp to the documented ceiling. We accept the
    // call (rather than rejecting) because production callers don't
    // expect their lease acquisition to ERROR on a TTL that's "too
    // generous"; clamping silently is the policy choice that gives the
    // best balance between catching arithmetic bugs (RT-H2 ceiling)
    // and tolerating legitimate "I don't care, just bound it" callers.
    let ttl_ms = ttl_ms.min(MAX_LEASE_TTL_MS);
    // `local_sync_owner.updated_at` is `INTEGER` so we bind
    // `now_epoch_ms` as an integer everywhere — both the WHERE-clause
    // expiry compare and the `updated_at` write. Mixing an INTEGER
    // bind for the WHERE and a TEXT bind for the column would let
    // STRICT mode reject the row anyway; binding the integer form
    // end-to-end is the contract.
    //
    // The expiry predicate is strict-less-than
    // (`expires_at_epoch_ms < ?4`). At `expires_at_epoch_ms == now_ms`
    // the lease is technically still alive for one more wall-clock
    // tick; a non-strict `<=` admitted the new owner exactly at the
    // boundary, which two surfaces racing through the same `now_ms`
    // could both pass — both entered the "I won the lease" branch and
    // produced overlapping work. Strict-less-than makes the boundary
    // belong to the prior owner and pushes the race onto the next ms;
    // current writers only install future expiries because non-positive
    // TTLs are rejected before this statement runs.
    let expires_at_epoch_ms = now_epoch_ms.saturating_add(ttl_ms);
    let rows_affected = conn.execute(
        "INSERT INTO local_sync_owner (lease_name, owner_id, expires_at_epoch_ms, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(lease_name) DO UPDATE SET
             owner_id            = excluded.owner_id,
             expires_at_epoch_ms = excluded.expires_at_epoch_ms,
             updated_at          = excluded.updated_at
         WHERE local_sync_owner.owner_id = excluded.owner_id
            OR local_sync_owner.expires_at_epoch_ms < ?4",
        params![lease_name, owner_id, expires_at_epoch_ms, now_epoch_ms],
    )?;
    Ok(rows_affected > 0)
}

/// caller-clock-free variant that reads
/// `current_timestamp_ms()` internally. Production code paths should
/// use this entry point so a transport whose `chrono::Utc::now()`
/// snapshot drifts (e.g. NTP correction after wake-from-sleep) cannot
/// silently install a lease that's already past its expiry — the
/// runtime crate owns the wall clock and does the math in one step.
///
/// The externally-clocked variant ([`try_acquire_sync_owner`]) is
/// retained for tests that need deterministic timestamps, but the
/// production-only constructor here is the recommended call site.
pub fn try_acquire_sync_owner_now(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    ttl_ms: i64,
) -> RuntimeResult<bool> {
    // Lease math uses the overflow-rejecting timestamp accessor so a
    // year-2262 clock surface as a typed `SystemClockOutOfRange` error
    // instead of silently saturating to `i64::MAX` and pinning the
    // lease forever.
    let now_epoch_ms = crate::local_state::current_timestamp_ms_for_lease()?;
    try_acquire_sync_owner(conn, lease_name, owner_id, now_epoch_ms, ttl_ms)
}

/// Explicit lease renewal API. Long-running syncs can outlive the lease's TTL
/// when filesystem or network latency spikes. This API bumps the TTL of the
/// lease only if we
/// still hold it. If the lease was lost (some other owner now holds
/// the row) or expired and stolen by someone else, the UPDATE
/// matches zero rows and we return `false`, signalling the caller to
/// abort the in-flight work rather than continue under the false
/// belief that we still own the lease. Re-issuing
/// `try_acquire_sync_owner` instead would silently transition a
/// lost lease back to ours if the rival's TTL had also elapsed —
/// "ours, lost it, took it back" would look indistinguishable from
/// "still ours" to the caller.
///
/// SQL contract: `UPDATE local_sync_owner SET expires_at_epoch_ms = ?
/// WHERE lease_name = ? AND owner_id = ? AND expires_at_epoch_ms > ?`
/// — the strict-greater predicate on `expires_at_epoch_ms` ensures we
/// only renew a lease that is still live for us at the wall-clock
/// instant the caller observed. A lease that has already expired (even
/// if no one else has stolen it yet) cannot be renewed; the caller
/// must call `try_acquire_sync_owner` to take it cleanly.
fn renew_sync_owner(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    now_epoch_ms: i64,
    ttl_ms: i64,
) -> RuntimeResult<bool> {
    if ttl_ms < 1 {
        return Err(RuntimeError::InvalidLeaseTtl(ttl_ms));
    }
    let ttl_ms = ttl_ms.min(MAX_LEASE_TTL_MS);
    let new_expires_at = now_epoch_ms.saturating_add(ttl_ms);
    let rows_affected = conn.execute(
        "UPDATE local_sync_owner
            SET expires_at_epoch_ms = ?1,
                updated_at          = ?4
          WHERE lease_name = ?2
            AND owner_id   = ?3
            AND expires_at_epoch_ms > ?4",
        params![new_expires_at, lease_name, owner_id, now_epoch_ms],
    )?;
    Ok(rows_affected > 0)
}

pub fn release_sync_owner(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
) -> RuntimeResult<bool> {
    let deleted = conn.execute(
        "DELETE FROM local_sync_owner WHERE lease_name = ?1 AND owner_id = ?2",
        [lease_name, owner_id],
    )?;
    Ok(deleted > 0)
}

/// Acquire a sync owner lease and return an RAII [`SyncOwnerLeaseGuard`]
/// that releases on drop. Callers MUST bind the
/// returned guard before any post-acquire logic that could panic
/// (e.g. `let Some(guard) = try_acquire_sync_owner_with_guard(...)?
/// else { return ...; };`). A panic between acquire and guard
/// installation would otherwise pin the lease for the full TTL.
///
/// `conn_factory` is the closure used by the guard's `Drop` to open
/// a fresh connection at release time — pass the surface's normal
/// `get_conn`-shaped closure, NOT a closure that captures the
/// caller's current connection (the connection may already be
/// dropped by the time `Drop` runs, intentionally so that the
/// writer mutex isn't held across network I/O).
fn try_acquire_sync_owner_with_guard<F>(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    now_epoch_ms: i64,
    ttl_ms: i64,
    release_fn: F,
    on_release_panic: ReleasePanicHook,
) -> RuntimeResult<Option<SyncOwnerLeaseGuard>>
where
    F: FnOnce(&str, &str) + Send + 'static,
{
    let acquired = try_acquire_sync_owner(conn, lease_name, owner_id, now_epoch_ms, ttl_ms)?;
    if !acquired {
        return Ok(None);
    }
    Ok(Some(SyncOwnerLeaseGuard::new(
        lease_name.to_string(),
        owner_id.to_string(),
        Box::new(release_fn),
        on_release_panic,
    )))
}

/// caller-clock-free variant of
/// [`try_acquire_sync_owner_with_guard`]. Production transports should reach
/// for this entry point so the runtime crate owns the wall clock and a
/// transport whose `chrono::Utc::now()` snapshot drifts (e.g. NTP correction
/// after wake-from-sleep) can't silently install a lease that's already past
/// its expiry. The externally-clocked variant is retained for tests that need
/// deterministic timestamps.
pub fn try_acquire_sync_owner_with_guard_now<F>(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    ttl_ms: i64,
    release_fn: F,
    on_release_panic: ReleasePanicHook,
) -> RuntimeResult<Option<SyncOwnerLeaseGuard>>
where
    F: FnOnce(&str, &str) + Send + 'static,
{
    let now_epoch_ms = crate::local_state::current_timestamp_ms_for_lease()?;
    try_acquire_sync_owner_with_guard(
        conn,
        lease_name,
        owner_id,
        now_epoch_ms,
        ttl_ms,
        release_fn,
        on_release_panic,
    )
}

/// caller-clock-free variant of [`renew_sync_owner`]. Production callers loop
/// calls to this between batches so the lease window tracks the wall clock the
/// runtime crate observes — never the caller's snapshot, which may have drifted
/// since acquisition. Returns `false` if the lease was lost or has already
/// expired (caller must abort), `true` if the renewal extended the live lease.
pub fn renew_sync_owner_now(
    conn: &Connection,
    lease_name: &str,
    owner_id: &str,
    ttl_ms: i64,
) -> RuntimeResult<bool> {
    let now_epoch_ms = crate::local_state::current_timestamp_ms_for_lease()?;
    renew_sync_owner(conn, lease_name, owner_id, now_epoch_ms, ttl_ms)
}
