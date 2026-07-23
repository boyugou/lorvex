use lorvex_domain::time::format_sync_timestamp;

use crate::error::{AppError, AppResult};
use rusqlite::params;

/// when `PREF_TIMEZONE` changes, re-materialize every
/// pending `task_reminders.reminder_at` from its stored local
/// wall-clock anchor (`original_local_time` + `original_tz`). The
/// user's intent when they said "remind me at 9 AM" was a wall-clock
/// moment, not a fixed UTC instant — so moving Tokyo → NY should keep
/// "9 AM" as "9 AM in NY", not "20:00 previous day NY".
///
/// Design (Option-A, principled — mirrors the habit-reminder model):
/// every reminder carries the `HH:MM` + IANA zone it was created
/// under. On a PREF_TIMEZONE change we pull the reminder's local
/// calendar date in its original zone, combine it with the stored
/// `HH:MM`, resolve that naive local-datetime in the NEW zone, and
/// write the resulting UTC instant back. `original_tz` is overwritten
/// to the new zone so a subsequent change re-anchors correctly.
///
/// Rows are eligible only when:
/// - `dismissed_at` / `cancelled_at` are both NULL;
/// - no `task_reminder_delivery_state` row is marked `delivered`
///   (the device-local `notified_at` equivalent — once we've already
///   fired, shifting the time does nothing useful);
/// - `reminder_at` is still in the future;
/// - both `original_local_time` and `original_tz` are non-NULL
///   (legacy rows stay absolute-UTC; documented limitation).
pub(super) fn reanchor_task_reminders_on_timezone_change(
    conn: &rusqlite::Connection,
    _old_tz_name: &str,
    new_tz_name: &str,
) -> AppResult<()> {
    use chrono::TimeZone;
    let new_tz: chrono_tz::Tz = match new_tz_name.parse() {
        Ok(tz) => tz,
        Err(_) => return Ok(()), // unknown new tz — nothing safe to do
    };
    // produce the canonical millisecond-Z form so this
    // SELECT cutoff lex-compares correctly against the
    // `task_reminders.reminder_at` column, which is otherwise written
    // through `sync_timestamp_now` / `format_sync_timestamp` (see
    // `lorvex-domain/src/time/sync_timestamp.rs`).
    let now_utc = chrono::Utc::now();
    let now_str = format_sync_timestamp(now_utc);

    // Select eligible rows. We join against `task_reminder_delivery_state`
    // so already-delivered reminders don't get shifted to fire a second
    // time. Collect first — don't hold the read statement while writing.
    let mut stmt = conn.prepare_cached(
        "SELECT r.id, r.reminder_at, r.original_local_time, r.original_tz \
         FROM task_reminders r \
         LEFT JOIN task_reminder_delivery_state d ON d.reminder_id = r.id \
         WHERE r.dismissed_at IS NULL \
           AND r.cancelled_at IS NULL \
           AND r.reminder_at > ?1 \
           AND r.original_local_time IS NOT NULL \
           AND r.original_tz IS NOT NULL \
           AND (d.delivery_state IS NULL OR d.delivery_state != 'delivered')",
    )?;
    let rows: Vec<(String, String, String, String)> = stmt
        .query_map([&now_str], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    drop(stmt);

    for (reminder_id, reminder_at_str, local_time, original_tz_name) in rows {
        // Skip no-op rewrites: the anchor already points at the new zone.
        if original_tz_name == new_tz_name {
            continue;
        }
        let original_tz: chrono_tz::Tz = match original_tz_name.parse() {
            Ok(tz) => tz,
            Err(_) => continue, // stored anchor tz is garbage; leave row alone
        };
        let reminder_utc = match chrono::DateTime::parse_from_rfc3339(&reminder_at_str) {
            Ok(dt) => dt.with_timezone(&chrono::Utc),
            Err(_) => continue,
        };
        // The anchor's calendar date is whatever local date the reminder
        // was pointing at in its original zone — that is the "9 AM what day"
        // the user meant. Extract that naive date, paste the stored HH:MM
        // on top, then resolve the result in the NEW zone.
        let original_local = original_tz.from_utc_datetime(&reminder_utc.naive_utc());
        let anchor_date = original_local.date_naive();
        let Some((hour, minute)) = parse_hhmm(&local_time) else {
            continue;
        };
        let Some(naive_new) = anchor_date.and_hms_opt(hour, minute, 0) else {
            continue;
        };
        // DST gap/overlap: pick the earliest valid interpretation. Spring-
        // forward "2:30 AM" is pushed to 3:00 AM; fall-back "1:30 AM"
        // resolves to the earlier occurrence. This matches the behavior
        // of most calendar apps and is good enough for the reminder
        // surface — users can manually edit the edge case if needed.
        let new_local = match new_tz.from_local_datetime(&naive_new) {
            chrono::LocalResult::Single(dt) => dt,
            chrono::LocalResult::Ambiguous(earlier, _) => earlier,
            chrono::LocalResult::None => {
                // Walk forward until we land in a valid slot (DST gap).
                let mut probe = naive_new;
                let mut resolved: Option<chrono::DateTime<chrono_tz::Tz>> = None;
                for _ in 0..180 {
                    probe += chrono::Duration::minutes(1);
                    if let chrono::LocalResult::Single(dt) = new_tz.from_local_datetime(&probe) {
                        resolved = Some(dt);
                        break;
                    }
                }
                match resolved {
                    Some(dt) => dt,
                    None => continue,
                }
            }
        };
        let new_reminder_utc = new_local.with_timezone(&chrono::Utc);
        // write the re-anchored UTC instant in
        // canonical millisecond-Z form so the column stays single-
        // precision against `sync_timestamp_now` writers and does
        // not drift in lex-compares.
        let new_reminder_str = format_sync_timestamp(new_reminder_utc);
        let new_version = crate::hlc::generate_version_result()?;
        conn.execute(
            "UPDATE task_reminders \
             SET reminder_at = ?1, original_tz = ?2, version = ?3 \
             WHERE id = ?4",
            params![new_reminder_str, new_tz_name, new_version, reminder_id],
        )
        .map_err(AppError::from)?;
        crate::commands::enqueue_task_reminder_upsert(conn, &reminder_id)?;
    }
    Ok(())
}

/// Parse an `HH:MM` string into `(hour, minute)` 24-hour pair.
fn parse_hhmm(value: &str) -> Option<(u32, u32)> {
    let (h, m) = value.split_once(':')?;
    let hour: u32 = h.parse().ok()?;
    let minute: u32 = m.parse().ok()?;
    if hour > 23 || minute > 59 {
        return None;
    }
    Some((hour, minute))
}
