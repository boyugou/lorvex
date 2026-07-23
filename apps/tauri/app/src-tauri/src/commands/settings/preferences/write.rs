use lorvex_domain::preference_keys::{
    DEV_AT_RISK_NOTIFICATION_LAST_FIRED, DEV_MORNING_BRIEFING_LAST_FIRED,
    DEV_WEEKLY_REVIEW_LAST_FIRED, PREF_LANGUAGE,
};
use lorvex_domain::validation::{KV_KEY_MAX_CHARS, KV_VALUE_MAX_BYTES};

use crate::{
    commands::{
        enqueue_preference_delete, enqueue_preference_upsert, sync_timestamp_now,
        with_immediate_transaction, OptionalExt,
    },
    db::get_conn,
    error::{AppError, AppResult},
    event_bus,
};
use rusqlite::params;

use super::timezone_reanchor::reanchor_task_reminders_on_timezone_change;

#[tauri::command]
pub fn set_preference(key: String, value: String) -> Result<(), String> {
    // reject empty keys at the IPC boundary. The
    // inner writer also enforces this, but failing early avoids
    // opening a write transaction and looking up the (irrelevant)
    // path-shaped allowlist for an obviously bogus call.
    if key.is_empty() {
        return Err("preference key must not be empty".to_string());
    }
    set_preference_inner(key, value).map_err(String::from)
}

#[cfg(test)]
pub(crate) fn set_preference_with_conn_for_tests(
    conn: &rusqlite::Connection,
    key: &str,
    value: &str,
    now: &str,
) -> AppResult<()> {
    set_preference_with_conn(conn, key, value, now)
}

pub(super) fn set_preference_with_conn(
    conn: &rusqlite::Connection,
    key: &str,
    value: &str,
    now: &str,
) -> AppResult<()> {
    // length caps apply before any other work.
    let key_char_count = key.chars().count();
    if key_char_count > KV_KEY_MAX_CHARS {
        return Err(AppError::Validation(format!(
            "preference key length {} exceeds maximum {KV_KEY_MAX_CHARS}",
            key_char_count
        )));
    }
    if key.is_empty() {
        return Err(AppError::Validation(
            "preference key must not be empty".to_string(),
        ));
    }
    if value.len() > KV_VALUE_MAX_BYTES {
        return Err(AppError::Validation(format!(
            "preference '{key}' value length {} exceeds maximum {KV_VALUE_MAX_BYTES}",
            value.len()
        )));
    }
    // every writable preference key must be in the canonical allowlist. Without
    // this gate a renderer XSS or malformed deep-link could pollute the
    // preferences table with arbitrary keys. The allowlist lives in
    // `lorvex_domain::preference_keys` so adding a new preference requires an
    // explicit shared-types change.
    if !lorvex_domain::preference_keys::is_known_preference_key(key) {
        return Err(AppError::Validation(format!(
            "preference '{key}' is not a known preference key — \
             add it to lorvex_domain::ALL_KNOWN_PREFERENCE_KEYS"
        )));
    }
    // Refuse to enable the memory-lock biometric gate on platforms
    // that do not have a biometric authenticator wired up. Without
    // this rejection, a user toggling the lock on macOS would
    // CRDT-sync `memory_lock_enabled = true` to a Linux peer with no
    // way to satisfy the gate — the renderer suppresses the toggle UI
    // there, but the underlying preference would still flip, leaving
    // the settings panel showing "lock disabled" while the backing
    // row said otherwise. Reject at the IPC boundary so the local
    // device never writes the truthy value; the sync apply path
    // normalizes imported rows separately.
    if key == lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED
        && !crate::platform::biometrics::SUPPORTS_BIOMETRIC_LOCK
    {
        if let Ok(serde_json::Value::Bool(true)) = serde_json::from_str::<serde_json::Value>(value)
        {
            return Err(AppError::Validation(format!(
                "preference '{key}' cannot be set on this platform — \
                 no biometric authenticator is available. Disable the \
                 memory lock toggle on a peer device instead."
            )));
        }
    }
    // capture the old PREF_TIMEZONE value BEFORE write so
    // the reanchor sweep below can compute the offset delta. Stored as
    // canonical JSON (`"America/Los_Angeles"`); decode via serde so an
    // interior quote inside the timezone label cannot survive a naive
    // `trim_matches('"')` and corrupt the comparison.
    let old_timezone: Option<String> = if key == lorvex_domain::preference_keys::PREF_TIMEZONE {
        conn.query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            params![key],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(AppError::from)?
        .and_then(|raw| serde_json::from_str::<String>(&raw).ok())
    } else {
        None
    };

    // Parse the incoming value as canonical JSON exactly once. JSON
    // `null` is the clear sentinel — match on the parsed `Value::Null`
    // rather than raw string equality so trailing whitespace, mixed
    // case, or any other near-`"null"` form is handled consistently
    // with every other JSON path in the codebase.
    let parsed_value =
        crate::commands::parse_canonical_json_value(value, &format!("preference '{key}'"))?;

    if parsed_value.is_null() {
        // snapshot the row BEFORE the clear so the typed
        // `DeleteEnvelope` carries the value the user just discarded.
        // Skipped silently when the key has no row to snapshot — the
        // clear becomes a no-op and no envelope is enqueued.
        let pre_delete_snapshot =
            match crate::commands::load_preference_pre_delete_snapshot(conn, key) {
                Ok(snapshot) => Some(snapshot),
                Err(AppError::NotFound(_)) => None,
                Err(other) => return Err(other),
            };

        // clear is now LWW-gated on a strictly-newer
        // HLC stamp. Generate a clear-time version even though the
        // DELETE doesn't write any column from it — the stamp is
        // compared against the row's `version` to keep a stale local
        // clear from clobbering a newer remote `set_preference`.
        let clear_version = crate::hlc::generate_version_result()?;
        // `clear_preference` returns `usize` rows
        // deleted (matches every other `delete_*` repository helper).
        // Treat any non-zero count as "the clear actually wrote".
        let cleared = lorvex_store::repositories::preference_repo::clear_preference(
            conn,
            key,
            &clear_version,
        )
        .map_err(AppError::from)?;

        if cleared > 0 {
            if let Some(snapshot) = pre_delete_snapshot {
                enqueue_preference_delete(
                    conn,
                    crate::commands::DeleteEnvelope::new(key, snapshot),
                )?;
            }
        }
        return Ok(());
    }

    let normalized_value = serde_json::to_string(&parsed_value).map_err(AppError::from)?;
    let version = crate::hlc::generate_version_result()?;
    lorvex_store::repositories::preference_repo::set_preference(
        conn,
        key,
        &normalized_value,
        &version,
        now,
    )
    .map_err(AppError::from)?;

    enqueue_preference_upsert(conn, key, &normalized_value, now)?;

    // post-write reanchor for PREF_TIMEZONE. Only runs
    // when the new value differs from the observed old value, so
    // idempotent re-writes (e.g. the settings autosave retry path)
    // don't trigger cascading HLC bumps.
    if key == lorvex_domain::preference_keys::PREF_TIMEZONE {
        // decode the just-written timezone via the same
        // canonical JSON parser as `old_timezone`. The previous
        // `trim_matches('"')` form silently mishandled pathological JSON
        // strings — e.g. a timezone label containing an interior escaped
        // quote (`"foo\"bar"`) would round-trip as `foo\"bar` for the new
        // value but `foo"bar` for the old, making the equality check
        // wrong and either skipping a reanchor that should have run or
        // running an extra one against a bogus pair. Use `from_str` on
        // both sides for a strict round-trip.
        let new_tz_stripped = serde_json::from_str::<String>(&normalized_value).map_err(|e| {
            AppError::Internal(format!("failed to decode normalized timezone: {e}"))
        })?;
        if let Some(old_tz) = old_timezone {
            if old_tz != new_tz_stripped {
                reanchor_task_reminders_on_timezone_change(conn, &old_tz, &new_tz_stripped)?;
                // the at-risk / morning-briefing / weekly-
                // review "last fired" markers are YMD strings computed
                // against the OLD tz. After a timezone change their
                // semantics flip — either double-fire (marker is in
                // pre-date under new tz) or drop (marker appears
                // already-fired under new tz). Clear them so the next
                // notification tick recomputes cleanly against the new
                // zone. device_state is local-only so no sync bump.
                for marker_key in [
                    DEV_MORNING_BRIEFING_LAST_FIRED,
                    DEV_WEEKLY_REVIEW_LAST_FIRED,
                    DEV_AT_RISK_NOTIFICATION_LAST_FIRED,
                ] {
                    conn.execute(
                        "DELETE FROM device_state WHERE key = ?1",
                        params![marker_key],
                    )?;
                }
            }
        }
    }

    Ok(())
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn set_preference_inner(key: String, value: String) -> AppResult<()> {
    let conn = get_conn()?;
    with_immediate_transaction(&conn, |conn| {
        let now = sync_timestamp_now();
        set_preference_with_conn(conn, &key, &value, &now)?;
        Ok(())
    })?;
    event_bus::emit_data_changed(event_bus::Entity::Preference);

    // When the language preference changes, re-register the native
    // notification action categories so button titles ("Complete",
    // "Snooze") update to the new locale without an app restart. On
    // Windows this is a no-op — rich toast actions aren't wired in
    // this build — but we call it for API symmetry.
    if key == PREF_LANGUAGE {
        let new_locale = crate::menu_i18n::preferred_locale();
        crate::platform::notification_actions::register_notification_categories(&new_locale);
    }

    Ok(())
}
