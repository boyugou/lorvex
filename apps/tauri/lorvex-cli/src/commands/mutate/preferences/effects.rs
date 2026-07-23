//! Preference key/value mutations.
//!
//! `preferences` is the JSON KV table that stores user-tunable
//! settings. The CLI surface deliberately rejects user-scope keys
//! (timezone, theme, sync backend, language, etc.) — those are owned
//! by Settings and changing them through scripts is a recipe for
//! drift. Agent-writable keys flow through `set_preference_with_conn`
//! / `delete_preference_with_conn` with the usual outbox + changelog
//! plumbing.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{ENTITY_PREFERENCE, OP_DELETE};
use lorvex_domain::validation::{KV_KEY_MAX_CHARS, KV_VALUE_MAX_BYTES};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::preference_repo;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{Connection, OptionalExtension};
use serde_json::json;

use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;
// #3497: typed `<entity>:<field>` extras key replaces the bare
// `"version"` slot. See `lorvex_workflow::mutation_extras`.
use lorvex_workflow::mutation_extras::PREFERENCE_VERSION;

/// Mutation descriptor for the CLI `set_preference` write — Phase 2
/// of #3452. The descriptor owns the version mint and the LWW-gated
/// repo write; the surrounding `set_preference_with_conn` keeps the
/// transaction policy, the outbox enqueue, the audit row write, and
/// the `local_change_seq` bump. The freshly-minted HLC version is
/// surfaced back to the caller through
/// `MutationOutput::get_extra(&PREFERENCE_VERSION)` (#3486 / #3508 —
/// the bare `"version"` literal became a typed `MutationExtraKey`) —
/// the CLI's `PreferenceSetResult` carries it on the API.
struct SetPreferenceMutation<'a> {
    key: &'a str,
    value_json: &'a str,
    now: &'a str,
    operation: &'static str,
    before_json: Option<&'a serde_json::Value>,
}

impl<'a> Mutation for SetPreferenceMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(self.before_json.cloned())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        preference_repo::set_preference(conn, self.key, self.value_json, &version, self.now)?;
        let after = json!({
            "key": self.key,
            "value": self.value_json,
            "version": version,
            "updated_at": self.now,
        });
        let summary = format!("Set preference \"{}\"", self.key);
        let mut output = MutationOutput::new(after, summary);
        output.set_extra(&PREFERENCE_VERSION, serde_json::Value::String(version));
        Ok(output)
    }
}

struct DeletePreferenceMutation<'a> {
    key: &'a str,
    before_json: &'a serde_json::Value,
}

impl<'a> Mutation for DeletePreferenceMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let deleted = preference_repo::clear_preference(conn, self.key, &version)? > 0;
        let mut output = MutationOutput::new(
            json!({
                "key": self.key,
                "deleted": deleted,
                "version": version,
            }),
            format!("Deleted preference '{}' (restored to default)", self.key),
        );
        output.set_extra(&PREFERENCE_VERSION, serde_json::Value::String(version));
        Ok(output)
    }
}

const CLI_FORBIDDEN_PREFERENCE_KEYS: &[&str] = &[
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PreferenceSetResult {
    pub(crate) key: String,
    pub(crate) value: serde_json::Value,
    pub(crate) updated_at: String,
    pub(crate) version: String,
    pub(crate) operation: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PreferenceDeleteResult {
    pub(crate) key: String,
    pub(crate) deleted: bool,
}

fn validate_preference_key_for_write(key: &str) -> Result<(), crate::error::CliError> {
    if key.is_empty() {
        return Err(crate::error::CliError::Validation(
            "preference key must not be empty".to_string(),
        ));
    }
    let char_count = key.chars().count();
    if char_count > KV_KEY_MAX_CHARS {
        return Err(crate::error::CliError::Validation(format!(
            "preference key exceeds maximum length ({char_count} chars, limit {KV_KEY_MAX_CHARS})"
        )));
    }
    if CLI_FORBIDDEN_PREFERENCE_KEYS.contains(&key) {
        return Err(crate::error::CliError::Validation(format!(
            "preference '{key}' is user-scope only; change it from Settings"
        )));
    }
    Ok(())
}

fn parse_preference_value_arg(
    key: &str,
    value_json: &str,
) -> Result<serde_json::Value, crate::error::CliError> {
    let value: serde_json::Value = serde_json::from_str(value_json).map_err(|error| {
        crate::error::CliError::Validation(format!(
            "preference '{key}' value must be valid JSON: {error}"
        ))
    })?;
    if let serde_json::Value::String(raw) = &value {
        if serde_json::from_str::<String>(raw).is_ok() {
            return Err(crate::error::CliError::Validation(format!(
                "preference '{key}' string values must be plain JSON strings, not double-encoded JSON string literals"
            )));
        }
    }
    let serialized = serde_json::to_string(&value)?;
    let byte_count = serialized.len();
    if byte_count > KV_VALUE_MAX_BYTES {
        return Err(crate::error::CliError::Validation(format!(
            "preference value exceeds maximum length ({byte_count} bytes, limit {KV_VALUE_MAX_BYTES})"
        )));
    }
    Ok(value)
}

pub(crate) fn enqueue_preference_upsert(
    conn: &Connection,
    device_id: &str,
    key: &str,
    value_json: &str,
    version: &str,
    updated_at: &str,
) -> Result<(), crate::error::CliError> {
    if lorvex_domain::preference_keys::is_local_only_preference(key) {
        return Ok(());
    }

    let payload =
        lorvex_store::payload_loaders::preference_upsert_payload(key, value_json, updated_at)?;
    enqueue_payload_upsert(
        conn,
        ENTITY_PREFERENCE,
        key,
        &payload,
        crate::commands::shared::bare_outbox_ctx(version, device_id),
    )?;
    Ok(())
}

fn enqueue_preference_delete(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    key: &str,
    before_value_json: &str,
    before_version: &str,
    before_updated_at: &str,
) -> Result<(), crate::error::CliError> {
    if lorvex_domain::preference_keys::is_local_only_preference(key) {
        return Ok(());
    }

    let version = hlc_state.generate().to_string();
    let payload = json!({
        "key": key,
        "value": before_value_json,
        "version": before_version,
        "updated_at": before_updated_at,
    });
    enqueue_payload_delete(
        conn,
        ENTITY_PREFERENCE,
        key,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}

pub(crate) fn set_preference_with_conn(
    conn: &mut Connection,
    key: &str,
    value_json_arg: &str,
) -> Result<PreferenceSetResult, crate::error::CliError> {
    validate_preference_key_for_write(key)?;
    let value = parse_preference_value_arg(key, value_json_arg)?;
    let value_json = serde_json::to_string(&value)?;
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;

    // capture pre-mutation snapshot for the audit trail.
    let before_row: Option<(String, String, String)> = tx
        .query_row(
            "SELECT value, version, updated_at FROM preferences WHERE key = ?1",
            [key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let existed = before_row.is_some();
    let before_json = before_row.as_ref().map(|(value, version, updated_at)| {
        json!({
            "key": key,
            "value": value,
            "version": version,
            "updated_at": updated_at,
        })
    });
    let now = lorvex_domain::sync_timestamp_now();
    let operation: &'static str = if existed { "update" } else { "create" };

    let mut hlc_guard = lock_shared(&tx)?;
    let mutation = SetPreferenceMutation {
        key,
        value_json: value_json.as_str(),
        now: now.as_str(),
        operation,
        before_json: before_json.as_ref(),
    };

    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let version = execution
                .output
                .get_extra(&PREFERENCE_VERSION)
                .and_then(|v| v.as_str())
                .map(str::to_string)
                .expect("Mutation contract: set_preference must stamp preference:version");
            enqueue_preference_upsert(&tx, &device_id, key, &value_json, &version, &now)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: key,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    // #3486: the descriptor surfaces the freshly-minted HLC version
    // through `MutationOutput.extra[PREFERENCE_VERSION]` instead of a
    // sibling `Cell<Option<String>>` out-param. #3497: the
    // `SetPreferenceMutation::apply` impl above unconditionally stamps
    // this key before returning `Ok`, so the read-back is a contract
    // assertion — convert the dead defensive `ok_or_else` branch to
    // `expect` so a contract violation panics loudly instead of
    // surfacing as a misleading `CliError::Validation`.
    let version = output
        .get_extra(&PREFERENCE_VERSION)
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .expect("Mutation contract: set_preference must stamp preference:version");
    drop(hlc_guard);
    tx.commit()?;

    Ok(PreferenceSetResult {
        key: key.to_string(),
        value,
        updated_at: now,
        version,
        operation,
    })
}

pub(crate) fn delete_preference_with_conn(
    conn: &mut Connection,
    key: &str,
) -> Result<PreferenceDeleteResult, crate::error::CliError> {
    validate_preference_key_for_write(key)?;
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before: Option<(String, String, String)> = tx
        .query_row(
            "SELECT value, version, updated_at FROM preferences WHERE key = ?1",
            [key],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let Some((before_value, before_version, before_updated_at)) = before else {
        // rollback the empty transaction rather than
        // committing it. Functionally identical (no writes happened),
        // but rollback signals "we did nothing" and avoids a no-op
        // COMMIT that pretends a state change took place.
        tx.rollback()?;
        return Ok(PreferenceDeleteResult {
            key: key.to_string(),
            deleted: false,
        });
    };

    let before_json = json!({
        "key": key,
        "value": before_value,
        "version": before_version,
        "updated_at": before_updated_at,
    });
    let mutation = DeletePreferenceMutation {
        key,
        before_json: &before_json,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let deleted = execution
                .output
                .after
                .get("deleted")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false);
            if !deleted {
                return Ok(());
            }
            enqueue_preference_delete(
                &tx,
                hlc_state,
                &device_id,
                key,
                &before_value,
                &before_version,
                &before_updated_at,
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: key,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let deleted = output
        .after
        .get("deleted")
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false);
    drop(hlc_guard);
    if !deleted {
        // same empty-txn rollback as the no-row
        // branch above — the LWW gate rejected the clear, no row was
        // touched, no COMMIT to perform.
        tx.rollback()?;
        return Ok(PreferenceDeleteResult {
            key: key.to_string(),
            deleted: false,
        });
    }
    tx.commit()?;

    Ok(PreferenceDeleteResult {
        key: key.to_string(),
        deleted: true,
    })
}
