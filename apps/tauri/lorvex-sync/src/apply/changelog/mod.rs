//! ai_changelog apply handler with dedup by `id` (primary key).
//!
//! The changelog is an append-only audit stream. Entries are never updated via
//! LWW; instead, duplicate detection by `id` alone prevents the same entry
//! from being inserted twice when synced from multiple devices.

use rusqlite::{params, Connection};

use lorvex_domain::capability::{check_envelope_version, EnvelopeAcceptance};
use lorvex_domain::version::PAYLOAD_SCHEMA_VERSION;

use super::ApplyError;

/// cap on the post-scrub `summary` length stored in
/// `ai_changelog`. Generous enough to cover legitimate batched
/// summaries (e.g. "Updated 50 tasks: …") while keeping a single
/// malicious envelope from pinning megabytes of text per row. The
/// app surfaces summary in Settings → Diagnostics; the cap applies
/// post-NFC normalization so it bounds storage, not glyph count.
const MAX_SUMMARY_LEN: usize = 4096;

/// cap on `before_json` / `after_json` post-scrub size.
/// 64 KiB is generous (a full task aggregate snapshot with attendees
/// fits in <8 KiB; a habit + 12-month completions fits in <16 KiB)
/// while preventing a hostile peer from pinning megabytes per
/// envelope. Without this cap a single peer can flood the cluster
/// with multi-megabyte audit rows that the retention pipeline only
/// GCs by age, not size.
const MAX_BEFORE_AFTER_JSON_LEN: usize = 64 * 1024;

/// cap on the changelog `id` (envelope-supplied PK).
/// All Lorvex-produced changelog ids are UUIDv7 (36 chars). Allow a
/// modest slack for forward-compat alternate forms while rejecting
/// peers running a forked builder that submit 250-byte non-UUIDs
/// (would render unbounded primary-key strings in Settings →
/// Diagnostics queries that assume UUIDv7 shape).
const MAX_CHANGELOG_ID_LEN: usize = 64;

/// cap on the changelog row's `target_entity_id`
/// field — distinct from the changelog row's own `id` because this
/// references an entity in another table. UUIDv7 (36 chars) for
/// every aggregate root; composite ids (`task_id:tag_id` etc.) for
/// edges add at most 2× UUID lengths plus a colon.
const MAX_TARGET_ENTITY_ID_LEN: usize = 80;

/// Recursively walk a JSON document and scrub every string value
/// through `sanitize_user_text`, then re-serialize to a canonical
/// shape. Object keys are NOT scrubbed — they're schema-defined and
/// cannot be attacker-controlled. Returns the re-serialized JSON
/// string ready for SQL binding.
///
/// applied to `before_json` / `after_json` so a
/// peer cannot embed bidi/zero-width controls inside a structured
/// snapshot that the Activity / undo / restore UI later renders.
fn scrub_json_string_values(raw: &str) -> Result<String, ApplyError> {
    let mut value: serde_json::Value = serde_json::from_str(raw)?;
    scrub_value_in_place(&mut value);
    Ok(serde_json::to_string(&value)?)
}

fn scrub_value_in_place(value: &mut serde_json::Value) {
    match value {
        serde_json::Value::String(s) => {
            *s = lorvex_domain::sanitize_user_text(s);
        }
        serde_json::Value::Array(items) => {
            for item in items {
                scrub_value_in_place(item);
            }
        }
        serde_json::Value::Object(map) => {
            for (_, v) in map.iter_mut() {
                scrub_value_in_place(v);
            }
        }
        _ => {}
    }
}

// JSON-extraction primitives now live in `apply::json_helpers`
//. The shared `optional_str` raises
// "must be a string when present" instead of the previous "must be a
// string or null" — both are accurate for the absent/null/string
// shape, and standardizing on the rest-of-apply wording avoids the
// need for a per-module bespoke variant.
use super::json_helpers::{
    optional_str, required_bool_as_i64, required_nullable_str, required_str,
};

/// Validate a string column against the schema's
/// `length(value) > 0 AND value = trim(value)` CHECK contract. Audit
/// finding: `apply_changelog_entry` bound peer-supplied
/// strings verbatim — a payload with `operation = " create "` (or
/// any whitespace-padded value) trimmed at INSERT time would trip
/// the CHECK and abort the entire apply batch. Validate at the
/// trust boundary in Rust so we fail with a clean
/// `ApplyError::InvalidPayload` (deferrable to `sync_pending_inbox`)
/// instead of poisoning the transaction.
fn require_trimmed_nonempty<'a>(
    val: &'a serde_json::Value,
    key: &str,
    entity: &str,
) -> Result<&'a str, ApplyError> {
    let raw = required_str(val, key, entity)?;
    if raw.is_empty() {
        return Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must not be empty"
        )));
    }
    if raw.trim() != raw {
        return Err(ApplyError::InvalidPayload(format!(
            "{entity} payload: {key} must not have leading/trailing whitespace"
        )));
    }
    Ok(raw)
}

/// Apply a changelog entry. Dedup by `id` (primary key): if an entry with
/// the same id already exists, skip silently.
///
/// `INSERT OR IGNORE` provides atomic dedup on the PK conflict, and
/// `conn.changes()` exposes "did we actually insert" if the caller
/// ever needs the signal — no separate `SELECT COUNT(*) > 0` pre-
/// check is needed.
///
/// The envelope's `payload_schema_version` threads through so the
/// changelog handler enforces a stricter version gate than ordinary
/// LWW-backed entities. The append-only changelog has no `version`
/// column, so a one-version-ahead payload cannot be safely inserted
/// with unknown fields truncated and later repaired by payload-shadow
/// promotion: replaying the same id would `INSERT OR IGNORE` no-op and
/// clear the shadow. Only `ParseFully` proceeds here; forward-compatible
/// or too-new payloads are refused so the envelope-level path can defer
/// them until the schema can fully parse the row.
pub(crate) fn apply_changelog_entry(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    payload_schema_version: u32,
) -> Result<(), ApplyError> {
    match check_envelope_version(payload_schema_version, PAYLOAD_SCHEMA_VERSION) {
        EnvelopeAcceptance::ParseFully => {}
        EnvelopeAcceptance::ParseForwardCompat | EnvelopeAcceptance::DeferToPendingInbox => {
            return Err(ApplyError::InvalidPayload(format!(
                "ai_changelog payload_schema_version {payload_schema_version} \
                 is not fully understood by local schema {PAYLOAD_SCHEMA_VERSION}; \
                 defer the changelog envelope until the audit row can be parsed without \
                 truncating forward-compatible fields"
            )));
        }
    }
    // cap the changelog row's PK length so a peer
    // running a forked builder can't bloat Settings → Diagnostics
    // with megabyte-long IDs.
    if entity_id.len() > MAX_CHANGELOG_ID_LEN {
        return Err(ApplyError::InvalidPayload(format!(
            "ai_changelog id exceeds {MAX_CHANGELOG_ID_LEN}-char limit (got {} chars)",
            entity_id.len()
        )));
    }

    let val: serde_json::Value = serde_json::from_str(payload)?;

    let timestamp = require_trimmed_nonempty(&val, "timestamp", "ai_changelog")?;
    let operation = require_trimmed_nonempty(&val, "operation", "ai_changelog")?;
    let entity_type = require_trimmed_nonempty(&val, "entity_type", "ai_changelog")?;
    let target_entity_id = optional_str(&val, "entity_id", "ai_changelog")?;
    // Cap target_entity_id length AND scrub through
    // `sanitize_user_text` — the field renders verbatim in Settings
    // → Diagnostics, so a unicode-poisoned target id could hijack
    // the renderer. The other text fields go through
    // `require_trimmed_nonempty`, which is enum-shaped data — this
    // one carries an entity reference so we sanitize without
    // requiring trim-equality (callers may send raw UUIDs).
    let target_entity_id_scrubbed = target_entity_id.map(lorvex_domain::sanitize_user_text);
    if let Some(ref t) = target_entity_id_scrubbed {
        if t.len() > MAX_TARGET_ENTITY_ID_LEN {
            return Err(ApplyError::InvalidPayload(format!(
                "ai_changelog payload: entity_id exceeds {MAX_TARGET_ENTITY_ID_LEN}-char limit \
                 (got {} chars after sanitization)",
                t.len()
            )));
        }
    }
    let entity_ids = optional_str(&val, "entity_ids", "ai_changelog")?;
    let summary = required_str(&val, "summary", "ai_changelog")?;
    if summary.is_empty() {
        return Err(ApplyError::InvalidPayload(
            "ai_changelog payload: summary must not be empty".to_string(),
        ));
    }
    // scrub free-text `summary` at the sync trust
    // boundary. The Settings → Diagnostics view renders this string
    // verbatim, so a peer running an older or malicious build that
    // pushes bidi overrides, zero-width controls, or LSEP would
    // hijack the renderer. Mirror the pattern every other text-bearing
    // aggregate-apply handler already uses.
    let summary_scrubbed = lorvex_domain::sanitize_user_text(summary);
    // Cap the post-scrub length so a single envelope can't pin a
    // megabyte of summary text into ai_changelog. The retention
    // pipeline applies its own cleanup but won't shrink an already-
    // committed row.
    if summary_scrubbed.len() > MAX_SUMMARY_LEN {
        return Err(ApplyError::InvalidPayload(format!(
            "ai_changelog payload: summary exceeds {MAX_SUMMARY_LEN}-char limit \
             (got {} chars after sanitization)",
            summary_scrubbed.len()
        )));
    }
    let initiated_by = require_trimmed_nonempty(&val, "initiated_by", "ai_changelog")?;
    let mcp_tool = optional_str(&val, "mcp_tool", "ai_changelog")?;
    let source_device_id_opt = optional_str(&val, "source_device_id", "ai_changelog")?;
    // #2373: structured before/after snapshots. Absent or null for
    // legacy rows, creates, deletes, and non-mutation operations.
    // also scrub string values inside the structured
    // snapshots — they're surfaced in Activity / undo / restore UI.
    let before_json = optional_str(&val, "before_json", "ai_changelog")?
        .map(scrub_json_string_values)
        .transpose()?;
    let after_json = optional_str(&val, "after_json", "ai_changelog")?
        .map(scrub_json_string_values)
        .transpose()?;
    // cap the post-scrub length of structured
    // snapshots. A peer can otherwise pin gigabytes per cluster
    // device per day — `summary` already had a 4 KiB cap; the
    // structured snapshots had no cap at all.
    if let Some(ref b) = before_json {
        if b.len() > MAX_BEFORE_AFTER_JSON_LEN {
            return Err(ApplyError::InvalidPayload(format!(
                "ai_changelog payload: before_json exceeds {MAX_BEFORE_AFTER_JSON_LEN}-byte \
                 limit (got {} bytes after sanitization)",
                b.len()
            )));
        }
    }
    if let Some(ref a) = after_json {
        if a.len() > MAX_BEFORE_AFTER_JSON_LEN {
            return Err(ApplyError::InvalidPayload(format!(
                "ai_changelog payload: after_json exceeds {MAX_BEFORE_AFTER_JSON_LEN}-byte \
                 limit (got {} bytes after sanitization)",
                a.len()
            )));
        }
    }

    // Current changelog payload builders always emit both fields:
    // `undo_token` is nullable, while `is_preview` is a required bool.
    // Missing fields indicate a malformed or legacy pre-release
    // envelope and must fail closed instead of falling back to schema
    // defaults.
    let undo_token = required_nullable_str(&val, "undo_token", "ai_changelog")?;
    let is_preview_value = required_bool_as_i64(&val, "is_preview", "ai_changelog")?;

    let changed = conn
        .prepare_cached(
            "INSERT OR IGNORE INTO ai_changelog
                 (id, timestamp, operation, entity_type, entity_id,
                  summary, initiated_by, mcp_tool, source_device_id,
                  before_json, after_json, undo_token, is_preview)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
        )?
        .execute(params![
            entity_id,
            timestamp,
            operation,
            entity_type,
            target_entity_id_scrubbed,
            summary_scrubbed,
            initiated_by,
            mcp_tool,
            source_device_id_opt,
            before_json,
            after_json,
            undo_token,
            is_preview_value,
        ])?;
    // The changelog is append-only and deduplicated by `id`. Only
    // populate the `ai_changelog_entities` join table when this
    // INSERT actually landed; replaying the same envelope must not
    // disturb a registry that already exists for the row.
    if changed > 0 {
        let ids = lorvex_store::changelog::entities::parse_entity_ids_json(entity_ids)
            .map_err(|e| ApplyError::InvalidPayload(format!("ai_changelog payload: {e}")))?;
        lorvex_store::changelog::replace_changelog_entities(conn, entity_id, &ids)?;
    }
    Ok(())
}

/// Apply the reset-only delete path for `ai_changelog`.
///
/// Ordinary changelog deletes remain invalid because the audit stream is
/// append-only outside full data reset. Reset envelopes must carry an explicit
/// marker so a hand-authored or buggy peer delete cannot erase audit rows by
/// accident.
pub(crate) fn apply_changelog_reset_delete(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
) -> Result<(), ApplyError> {
    if entity_id.len() > MAX_CHANGELOG_ID_LEN {
        return Err(ApplyError::InvalidPayload(format!(
            "ai_changelog id exceeds {MAX_CHANGELOG_ID_LEN}-char limit (got {} chars)",
            entity_id.len()
        )));
    }
    let val: serde_json::Value = serde_json::from_str(payload)?;
    if val
        .get("reset_all_data")
        .and_then(serde_json::Value::as_bool)
        != Some(true)
    {
        return Err(ApplyError::InvalidOperation {
            entity_type: lorvex_domain::naming::EntityKind::AiChangelog
                .as_str()
                .to_string(),
            operation: "delete".to_string(),
        });
    }
    if let Some(payload_id) = val.get("id").and_then(serde_json::Value::as_str) {
        if payload_id != entity_id {
            return Err(ApplyError::InvalidPayload(format!(
                "ai_changelog reset delete payload id '{payload_id}' does not match entity_id '{entity_id}'"
            )));
        }
    }
    conn.prepare_cached("DELETE FROM ai_changelog WHERE id = ?1")?
        .execute(params![entity_id])?;
    Ok(())
}

#[cfg(test)]
mod tests;
