//! Tombstone garbage collection — watermark-based primary sweep plus a
//! test-only fixed-retention fallback.

use rusqlite::{params, Connection};

/// Delete expired tombstones older than `retention_days` (fixed-retention fallback).
///
/// Returns the number of deleted tombstones.
///
/// This is the simpler fallback GC. Prefer [`gc_tombstones_watermark`] as the
/// primary API, which is smarter about per-device sync state.
#[cfg(test)]
pub(super) fn gc_tombstones_fixed(
    conn: &Connection,
    retention_days: u32,
) -> Result<u64, rusqlite::Error> {
    let deleted = conn.execute(
        "DELETE FROM sync_tombstones
         WHERE deleted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        params![format!("-{retention_days} days")],
    )?;
    Ok(deleted as u64)
}

/// Version-domain watermark tombstone GC (primary API).
///
/// 1. Find the minimum `last_applied_version` (HLC) across all ACTIVE devices.
///    A device is "active" if its `last_sync_at` is within
///    `DEVICE_INACTIVE_THRESHOLD_DAYS` of now. The watermark is the lowest
///    HLC version any active device has applied.
/// 2. Delete tombstones where `version < watermark` (all active devices
///    have applied envelopes past this tombstone's version).
/// 3. In the watermark branch only, delete tombstones older than
///    `TOMBSTONE_MAX_RETENTION_DAYS` (wall-clock `deleted_at`) as an
///    absolute safety net for rows whose tainted `version` evaded the
///    lex-string watermark predicate. This step is
///    skipped on the no-watermark branch because the 180-day fallback
///    there already catches a strict superset of what the 365-day cap
///    would.
/// 4. If no active devices exist, only the max-retention fallback applies.
///
/// when ANY active device's `last_applied_version` is NULL,
/// the watermark is undefined for that device — we can't prove that device
/// has seen any tombstone. Suppress the watermark step entirely in that
/// case (don't fabricate a value from the non-NULL subset and silently
/// GC tombstones the NULL device may not have observed yet).
///
/// when no active device has reported a watermark
/// (single-device deployment, fresh install, or every device's
/// `last_applied_version` is NULL per #2964-M1), the GC otherwise has
/// no upper bound except the 365-day absolute safety net — meaning a
/// healthy single-device install accumulates a year of tombstones
/// before any reach the GC. Add a `DEVICE_INACTIVE_THRESHOLD_DAYS × 2`
/// (180-day) fallback retention horizon: well past the device's own
/// active threshold, so even a peer that goes silent at the active
/// boundary catches up before its tombstones are reaped.
///
/// Returns the total number of deleted tombstones.
pub fn gc_tombstones_watermark(conn: &Connection) -> Result<u64, rusqlite::Error> {
    let max_retention = lorvex_domain::naming::TOMBSTONE_MAX_RETENTION_DAYS;
    let inactive_threshold = lorvex_domain::naming::DEVICE_INACTIVE_THRESHOLD_DAYS;

    // Step 1: Find the minimum last_applied_version (HLC) among active devices.
    // A device is "active" if last_sync_at >= (now - inactive_threshold days).
    // The watermark is the lowest HLC version any active device has applied —
    // tombstones with version < watermark have been seen by all active devices.
    //
    // count active devices and the subset whose
    // last_applied_version is NULL in the same query as the MIN. If
    // any active device has NULL, the watermark is undefined and we
    // must NOT GC by version — the NULL device might not have applied
    // even the oldest tombstones yet.
    let (active_total, active_with_null, watermark): (i64, i64, Option<String>) = conn.query_row(
        "SELECT COUNT(*),
                    SUM(CASE WHEN last_applied_version IS NULL THEN 1 ELSE 0 END),
                    MIN(last_applied_version)
             FROM sync_device_cursors
             WHERE last_sync_at >= strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        params![format!("-{inactive_threshold} days")],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                // SUM over zero rows is NULL in SQLite — treat as 0.
                row.get::<_, Option<i64>>(1)?.unwrap_or(0),
                row.get::<_, Option<String>>(2)?,
            ))
        },
    )?;

    let mut total_deleted = 0u64;

    // Step 2: If every active device has reported a watermark version,
    // delete tombstones whose version (HLC) is less than the watermark.
    // HLC strings are lexicographically sortable, so string comparison
    // is correct. If any active device contributes NULL — or there are
    // no active devices at all — the watermark step is skipped.
    let have_full_watermark = active_total > 0 && active_with_null == 0 && watermark.is_some();
    if have_full_watermark {
        if let Some(ref wm) = watermark {
            let deleted = conn.execute(
                "DELETE FROM sync_tombstones WHERE version < ?1",
                params![wm],
            )?;
            total_deleted += deleted as u64;
        }
    } else {
        // no-watermark fallback. Reap tombstones older
        // than 2× the device-active threshold (well past any device's
        // legitimate offline window) so single-device installs and
        // fresh-cursor multi-device clusters don't wait the full
        // 365-day horizon to start reclaiming space.
        let fallback_retention = inactive_threshold.saturating_mul(2);
        let deleted = conn.execute(
            "DELETE FROM sync_tombstones
             WHERE deleted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
            params![format!("-{fallback_retention} days")],
        )?;
        total_deleted += deleted as u64;
    }

    // Step 3: Wall-clock safety net for the watermark branch only.
    // this DELETE is redundant in the no-watermark
    // branch above, which already reaps rows older than
    // `inactive_threshold * 2` (180 days) — strictly less than
    // `max_retention` (365 days). Running it there would always be a
    // no-op, so guard the step on `have_full_watermark`. Keeping the
    // step on the watermark branch is the safety net for tombstones
    // whose `version` is corrupt enough to not lex-compare against
    // the watermark string (e.g. a tainted envelope that survived
    // earlier validation gates).
    if have_full_watermark {
        let deleted = conn.execute(
            "DELETE FROM sync_tombstones
             WHERE deleted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
            params![format!("-{max_retention} days")],
        )?;
        total_deleted += deleted as u64;
    }

    Ok(total_deleted)
}
