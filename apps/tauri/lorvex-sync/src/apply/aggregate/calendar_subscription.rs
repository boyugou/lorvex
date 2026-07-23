//! Apply handlers for the `calendar_subscription` aggregate root.
//!
//! Subscription entries are synced for cross-device convergence on the
//! shared `name`/`url`/`color`/`enabled` shape, but the device-local
//! refresh state in `provider_scope_runtime_state` is deliberately not
//! deserialized here so an incoming envelope cannot reset another peer's
//! local fetch diagnostics.

use rusqlite::{named_params, Connection};

use super::super::LwwTieBreak;
use super::helpers::{optional_bool_as_i64, optional_str, required_str, scrub};
use super::ApplyError;

pub(crate) fn apply_calendar_subscription_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    // handler doesn't currently consume the apply
    // timestamp, but every aggregate-upsert signature carries it
    // for uniform dispatch — `_apply_ts` keeps the parameter shape
    // without the unused-variable warning.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Unicode hygiene (#2427): subscription display name is user-facing.
    // `url` is a structured field handled by URL parsing — not scrubbed.
    let name_owned = scrub(required_str(&val, "name", "calendar_subscription")?);
    let name: &str = &name_owned;
    // scheme allowlist on the apply trust boundary.
    // The local writer at `app/src-tauri/src/calendar_subscription_sync/
    // validation.rs` already restricts to http/https; this gate
    // closes the symmetric peer-envelope path. Reject `javascript:`,
    // `data:`, `file:`, etc. — only http/https/webcal are legitimate
    // calendar feed schemes. A peer running a forked builder could
    // otherwise write `url = "javascript:alert(1)"` straight into the
    // table, and any future surface that converts the column to an
    // `<a href>` (or that the user copies out of Settings → Calendar
    // Sources) is exploitable.
    let url_raw = required_str(&val, "url", "calendar_subscription")?;
    // bind the validator's canonical (sanitized +
    // trimmed) form to the INSERT, not the raw envelope value, so a
    // peer-supplied URL with leading bidi-override / zero-width
    // codepoints stops smuggling those bytes through the apply
    // pipeline into `calendar_subscriptions.url`.
    let url_canonical = lorvex_domain::validation::validate_calendar_url(url_raw).map_err(|e| {
        ApplyError::InvalidPayload(format!("calendar_subscription payload.url: {e}"))
    })?;
    let url = url_canonical.as_str();
    let color = optional_str(&val, "color", "calendar_subscription")?;
    // treat missing `enabled` as 1 (the UI default for
    // newly-created subscriptions and SQL column default).
    let enabled = optional_bool_as_i64(&val, "enabled", "calendar_subscription")?.unwrap_or(1);
    let created_at = required_str(&val, "created_at", "calendar_subscription")?;
    let updated_at = required_str(&val, "updated_at", "calendar_subscription")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "calendar_subscriptions",
        columns: &[
            "id",
            "name",
            "url",
            "color",
            "enabled",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": entity_id,
        ":name": name,
        ":url": url,
        ":color": color,
        ":enabled": enabled,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

/// defense-in-depth LWW guard. The upstream LWW
/// check at `apply/mod.rs` already protects this path when a local
/// row exists at apply time, but every other aggregate-delete
/// handler (task, list, habit, calendar_event) carries an
/// in-handler `WHERE ?2 >= version` predicate as a second line of
/// defense — most useful when an ordering bug or test path bypasses
/// the upper gate. Mirrors the pattern adopted across the rest of
/// the apply pipeline.
pub(crate) fn apply_calendar_subscription_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    // see `apply_calendar_subscription_upsert` for the rationale on
    // the `_apply_ts` rename.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    crate::apply::lww_gated_delete(
        conn,
        "calendar_subscriptions",
        &["id"],
        &[entity_id],
        version,
    )?;
    Ok(())
}
