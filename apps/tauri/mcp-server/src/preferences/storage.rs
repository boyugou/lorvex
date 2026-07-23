use crate::contract::{DeletePreferenceArgs, GetPreferenceArgs, SetPreferenceArgs};
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::{
    execute_mcp_mutation_with_finalizer, execute_mcp_mutation_with_undo_tombstone_audit_finalizer,
    log_change, LogChangeParams,
};
use crate::system::handler_support::utc_now_iso;
use crate::tasks::validation::validate_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_PREFERENCE, OP_DELETE};
use lorvex_domain::validation::{KV_KEY_MAX_CHARS, KV_VALUE_MAX_BYTES};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

fn parse_preference_value(key: &str, raw: &str) -> Result<Value, McpError> {
    serde_json::from_str::<Value>(raw).map_err(|error| {
        McpError::Validation(format!(
            "preference '{key}' contains malformed JSON: {error}"
        ))
    })
}

fn validate_preference_input_value(key: &str, value: &Value) -> Result<(), McpError> {
    if let Value::String(raw) = value {
        if serde_json::from_str::<String>(raw).is_ok() {
            return Err(McpError::Validation(format!(
                "preference '{key}' string values must be passed as plain strings, not JSON-encoded string literals"
            )));
        }
    }
    Ok(())
}

pub(crate) fn parse_preference_row_value(row: Value) -> Result<Value, McpError> {
    let Value::Object(mut object) = row else {
        return Err(McpError::Validation(
            "malformed preference row: expected JSON object".to_string(),
        ));
    };
    let key = object
        .get("key")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| McpError::Validation("malformed preference row: missing key".to_string()))?
        .to_string();
    let raw_value = object.get("value").and_then(Value::as_str).ok_or_else(|| {
        McpError::Validation(format!(
            "malformed preference row for '{key}': missing raw value"
        ))
    })?;
    object.insert(
        "value".to_string(),
        parse_preference_value(&key, raw_value)?,
    );
    Ok(Value::Object(object))
}

#[cfg(test)]
pub(crate) fn load_preference_row(conn: &Connection, key: &str) -> Result<Value, McpError> {
    query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [key.to_string()],
    )?
    .ok_or_else(|| McpError::NotFound(format!("Failed to load preference '{key}'")))
}

/// preference keys the MCP assistant MUST NOT touch.
///
/// These preferences have cross-cutting or trust-critical side effects
/// that should only be changed by deliberate user action through the
/// Settings UI:
///
///   - \`timezone\`: shifts every reminder (#2341 re-anchors task reminders,
///     but habit reminders / cached UI timestamps would silently drift).
///   - \`theme\` / \`appearance_profile\` / \`font_scale\`: user's aesthetic
///     choice; the assistant changing these without consent is
///     aggressive even if well-intentioned.
///   - \`ai_changelog_retention_policy\` / \`error_log_retention_days\`:
///     the assistant's own audit trail. Shortening retention is
///     self-shadowing — the assistant could erase the record of its
///     own prior writes.
///   - \`language\`: affects UI locale everywhere.
///   - \`sync_enabled\` / \`sync_backend_kind\` / \`sync_backend_configs\`:
///     cross-device data-movement policy; must be a user decision.
///   - \`memory_lock_enabled\`: gates the whole AI-memory surface.
///   - \`setup_completed\` / \`setup_state\`: onboarding state; the
///     assistant changing these would re-hide or re-show the welcome
///     flow unexpectedly.
///
/// Any other preference (dashboard layout, energy peak, quiet hours,
/// workflow preferences, etc.) remains assistant-settable — these are
/// the kinds of fine-tuning adjustments the assistant is legitimately
/// asked to make on the user's behalf.
///
/// Distinct from an allow-list: we prefer deny-list so new benign
/// preferences don't require churn here.
const MCP_FORBIDDEN_PREFERENCE_KEYS: &[&str] = &[
    lorvex_domain::preference_keys::PREF_TIMEZONE,
    lorvex_domain::preference_keys::PREF_THEME,
    lorvex_domain::preference_keys::PREF_APPEARANCE_PROFILE,
    lorvex_domain::preference_keys::PREF_FONT_SCALE,
    lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
    lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
    lorvex_domain::preference_keys::PREF_LANGUAGE,
    lorvex_domain::preference_keys::PREF_SYNC_ENABLED,
    lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
    lorvex_domain::preference_keys::PREF_SYNC_BACKEND_CONFIGS,
    lorvex_domain::preference_keys::PREF_MEMORY_LOCK_ENABLED,
    lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
    lorvex_domain::preference_keys::PREF_SETUP_STATE,
];

/// Mutation descriptor for the MCP `set_preference` tool. The
/// `operation` is decided by the caller based on whether the row
/// pre-existed (`"update"` vs `"create"`) and frozen as a
/// `&'static str` carried in the descriptor; the trait's `operation()`
/// accessor returns it verbatim. The `apply` method owns the version
/// mint and the LWW-gated repo write; the surrounding handler keeps
/// validation, sanitization, and the undo-token/audit-funnel call.
struct SetPreferenceMutation<'a> {
    key: &'a str,
    value_json: &'a str,
    now: &'a str,
    operation: &'static str,
    before: Option<&'a Value>,
}

impl<'a> Mutation for SetPreferenceMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.cloned())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        lorvex_store::repositories::preference_repo::set_preference(
            conn,
            self.key,
            self.value_json,
            &version,
            self.now,
        )?;
        let after = crate::json_row::query_one_as_json(
            conn,
            "SELECT key, value, updated_at FROM preferences WHERE key = ?",
            [self.key.to_string()],
        )
        .map_err(|e| StoreError::Invariant(format!("query_one_as_json: {e}")))?
        .ok_or_else(|| {
            StoreError::Invariant(format!("preference '{}' vanished after write", self.key))
        })?;
        let summary = format!("Set preference \"{}\"", self.key);
        Ok(MutationOutput::new(after, summary))
    }
}

struct DeletePreferenceMutation<'a> {
    key: &'a str,
    before: Option<&'a Value>,
    prior_value: Option<Value>,
}

impl<'a> Mutation for DeletePreferenceMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.cloned())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let clear_version = hlc.next_version_string();
        let deleted = lorvex_store::repositories::preference_repo::clear_preference(
            conn,
            self.key,
            &clear_version,
        )? > 0;

        if !deleted {
            return Ok(MutationOutput::new(
                json!({
                    "deleted": false,
                    "key": self.key,
                    "previous": Value::Null,
                }),
                format!("Skipped preference delete for '{}'", self.key),
            ));
        }

        Ok(MutationOutput::new(
            json!({
                "deleted": true,
                "key": self.key,
                "previous": self.prior_value,
            }),
            format!("Deleted preference '{}' (restored to default)", self.key),
        ))
    }
}

pub(crate) fn set_preference(
    conn: &Connection,
    args: SetPreferenceArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure so a retried set_preference
    // (which fans out to ai_changelog + sync envelope) short-
    // circuits.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let SetPreferenceArgs {
        key,
        mut value,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "set_preference",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_string_length(&key, "preference key", KV_KEY_MAX_CHARS)?;
    if MCP_FORBIDDEN_PREFERENCE_KEYS.contains(&key.as_str()) {
        return Err(McpError::Validation(format!(
            "preference '{key}' is user-scope only; the assistant cannot modify it. \
             Ask the user to change it from Settings."
        )));
    }
    // mirror the Tauri-side allowlist gate from
    // `app/src-tauri/src/commands/preferences.rs::set_preference_with_conn`.
    // Without this gate, the MCP setter (running with the same DB privileges
    // as the app) lets a misbehaving / hijacked assistant shove arbitrary keys
    // into the preferences table. The deny-list above only prevents touching
    // specific sensitive keys; this allowlist refuses every key the schema
    // doesn't explicitly know about.
    if !lorvex_domain::preference_keys::is_known_preference_key(&key) {
        return Err(McpError::Validation(format!(
            "preference '{key}' is not a known preference key — \
             add it to lorvex_domain::ALL_KNOWN_PREFERENCE_KEYS"
        )));
    }
    validate_preference_input_value(&key, &value)?;
    // preference values carry arbitrary JSON, including
    // nested string leaves the user typed (display names, free-text
    // tags, search-query strings stashed inside saved-filter blobs).
    // or zero-width joiner buried inside an object/array round-tripped
    // through the apply pipeline and back to the renderer with the
    // attack vector intact, defeating the #2427 hygiene gate at the
    // leaf. Walk the JSON tree and scrub every string leaf BEFORE the
    // length-cap check so multi-byte controls don't artificially
    // inflate the byte count past the cap.
    lorvex_domain::sanitize_user_text_in_json_in_place(&mut value);
    let value_json_preview = serde_json::to_string(&value)?;
    let value_byte_count = value_json_preview.len();
    if value_byte_count > KV_VALUE_MAX_BYTES {
        return Err(McpError::Validation(format!(
            "preference value exceeds maximum length ({value_byte_count} bytes, limit {KV_VALUE_MAX_BYTES})"
        )));
    }
    let now = utc_now_iso();
    let before = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [key.clone()],
    )?;

    let value_json = serde_json::to_string(&value)?;
    let operation: &'static str = if before.is_some() { "update" } else { "create" };

    let mutation = SetPreferenceMutation {
        key: key.as_str(),
        value_json: value_json.as_str(),
        now: now.as_str(),
        operation,
        before: before.as_ref(),
    };

    // #2367: capture the prior *value* (not the whole row) for the
    // undo token. If the key didn't exist before, `prior_value` stays
    // None and the revert path clears the key instead of restoring.
    // Parse the raw JSON string back to a `Value` so the revert
    // doesn't have to re-parse — the token carries the already-decoded
    // shape the set_preference API expects.
    let prior_value: Option<Value> = match before.as_ref() {
        Some(row) => match row.get("value").and_then(Value::as_str) {
            Some(raw) => Some(parse_preference_value(&key, raw)?),
            None => None,
        },
        None => None,
    };
    let expires_at = crate::runtime::undo::compute_undo_expiry();
    let undo =
        crate::runtime::undo::McpUndoToken::set_preference(key.clone(), prior_value, expires_at);
    let undo_token_json = undo.to_json_string()?;

    let output =
        execute_mcp_mutation_with_finalizer(conn, &mutation, McpError::from, |execution| {
            // On the create branch we MUST still record the post-write
            // row in `after_json`. `before_json` stays None (no prior
            // row); `after_json` mirrors the update branch and carries
            // the post-write `pref` row.
            let before_json = if operation == "update" {
                execution.before
            } else {
                None
            };
            log_change(
                conn,
                LogChangeParams::new(
                    execution.operation,
                    execution.entity_kind,
                    "set_preference",
                    execution.output.summary,
                )
                .with_entity_id(key.clone())
                .with_before_opt(before_json)
                .with_after(execution.output.after)
                .with_undo_token(undo_token_json.clone()),
                None,
            )
        })?;

    let response_pref = parse_preference_row_value(output.after)?;
    // #2367: wrap the parsed pref row with the undo token. The response
    // shape stays additive — existing consumers that only read `key` /
    // `value` / `updated_at` keep working unchanged.
    let mut response_obj = response_pref.as_object().cloned().unwrap_or_default();
    response_obj.insert("undo_token".to_string(), Value::String(undo_token_json));
    let response = serde_json::to_string(&Value::Object(response_obj))?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "set_preference",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

pub(crate) fn get_preference(
    conn: &Connection,
    args: GetPreferenceArgs,
) -> Result<String, McpError> {
    let GetPreferenceArgs { key } = args;
    let row = conn
        .query_row(
            "SELECT key, value, updated_at FROM preferences WHERE key = ?",
            [key],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                ))
            },
        )
        .optional()?;

    let Some((pref_key, value_raw, updated_at)) = row else {
        return Ok("null".to_string());
    };

    let parsed_value = parse_preference_value(&pref_key, &value_raw)?;
    let payload = json!({
        "key": pref_key,
        "value": parsed_value,
        "updated_at": updated_at,
    });

    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn delete_preference(
    conn: &Connection,
    args: DeletePreferenceArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // dry_run is consumed by the router-level
    // `dispatch_dry_run` wrapper; the body runs identically in
    // real and preview modes.
    let DeletePreferenceArgs {
        key,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_preference",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // same forbidden list as set_preference. Clearing a
    // sensitive preference reverts it to its default, which is a
    // behavioral change equivalent to setting.
    if MCP_FORBIDDEN_PREFERENCE_KEYS.contains(&key.as_str()) {
        return Err(McpError::Validation(format!(
            "preference '{key}' is user-scope only; the assistant cannot clear it. \
             Ask the user to change it from Settings."
        )));
    }

    // snapshot the pre-delete row so we can:
    //   * carry it as `before_json` on the changelog row,
    //   * return it as `previous` in the response (CLAUDE.md rule 5),
    //   * embed the prior value in an undo token so the assistant can
    //     offer a one-click "restore" affordance — symmetric with the
    //     `set_preference` path.
    let before = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [key.clone()],
    )?;

    let prior_value: Option<Value> = match before.as_ref() {
        Some(row) => match row.get("value").and_then(Value::as_str) {
            Some(raw) => Some(parse_preference_value(&key, raw)?),
            None => None,
        },
        None => None,
    };
    let expires_at = crate::runtime::undo::compute_undo_expiry();
    let undo = crate::runtime::undo::McpUndoToken::set_preference(
        key.clone(),
        prior_value.clone(),
        expires_at,
    );
    let undo_token_json = undo.to_json_string()?;

    // thread the captured pre-delete preference row
    // through the outbox tombstone payload so peers receive the
    // full prior `(key, value, updated_at)` rather than a degenerate
    // `{"id": key}` envelope. The funnel was already setting
    // `before_json: before.clone()` for the changelog row.
    let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    if let Some(before_value) = before.clone() {
        tombstones.insert(key.clone(), before_value);
    }

    let mutation = DeletePreferenceMutation {
        key: key.as_str(),
        before: before.as_ref(),
        prior_value,
    };
    let mut output = execute_mcp_mutation_with_undo_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_preference",
        key.clone(),
        undo_token_json.clone(),
        tombstones,
        McpError::from,
        |_, _| Ok(()),
    )?;

    if output.after.get("deleted").and_then(Value::as_bool) == Some(true) {
        if let Some(object) = output.after.as_object_mut() {
            object.insert("undo_token".to_string(), Value::String(undo_token_json));
        }
    }
    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_preference",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

pub(crate) fn get_all_preferences(conn: &Connection) -> Result<String, McpError> {
    let mut stmt = conn.prepare_cached("SELECT key, value FROM preferences ORDER BY key")?;

    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    let mut map = Map::new();
    for row in rows {
        let (key, raw_value) = row?;
        let parsed = parse_preference_value(&key, &raw_value)?;
        map.insert(key, parsed);
    }

    Ok(serde_json::to_string(&Value::Object(map))?)
}
