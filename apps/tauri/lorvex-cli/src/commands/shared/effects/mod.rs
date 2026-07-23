//! Shared utilities used across every `commands::mutate` submodule.
//!
//! - `log_cli_changelog` writes the CLI's audit-trail row and
//!   sync-replicates it. Every CLI mutation that should appear in the
//!   user's history funnels through here.
//! - The timezone helpers (`anchored_timezone_name_for_conn`,
//!   `today_ymd_for_conn`, `date_plus_days_ymd_for_conn`) are thin
//!   shortcuts over `lorvex_workflow::timezone::*` — they
//!   exist purely to spare 14+ call sites the long path prefix and
//!   convert `StoreError` into `CliError` via the `#[from]` impl.
//!   Active timezone reads route through
//!   `lorvex_workflow::timezone::active_timezone_name`
//!   directly so the CLI cannot drift from the canonical parser
//!   contract.
//! - `resolve_cli_actor_name` is internal to changelog rendering.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, ENTITY_PREFERENCE};
use lorvex_runtime::get_or_create_device_id;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{
    enqueue_entity_upsert, enqueue_payload_upsert, OutboxWriteContext,
};
use lorvex_workflow::mutation::{
    execute_with_context, Mutation, MutationContext, MutationExecution, MutationOutput,
};
use rusqlite::Connection;
use serde_json::{json, Value};

#[cfg(test)]
use crate::hlc_guard::next_hlc_version;
use crate::hlc_guard::CliHlcStateHandle;

/// stable `mcp_tool` discriminator stamped on every
/// CLI-originated `ai_changelog` row. The MCP server stamps the actual
/// tool name (`update_task`, `complete_task`, …); the Tauri app never
/// writes to `ai_changelog` (its `log_change` is a no-op). Tagging CLI
/// rows with `"cli"` lets export / activity classifiers cleanly
/// separate the three surfaces without regex-matching against
/// `initiated_by` (which can be `"human"`, `"ai"`, or any free-form
/// `LORVEX_AGENT_NAME` value).
const CLI_AI_CHANGELOG_TOOL: &str = "cli";

// Snapshot truncation, summary sanitization, and the canonical
// `ai_changelog` writer all live in `lorvex_workflow::
// changelog` so the MCP server, the CLI, and any future write surface
// share one implementation.
use lorvex_store::changelog::{encode_state_json, sanitize_changelog_summary};

/// honor `LORVEX_AGENT_NAME` on the CLI path. When an
/// agent (Claude Code etc.) shells out to `lorvex capture`, the
/// changelog said "human" did it, corrupting the
/// audit-trail signal the review UX depends on. Unset or empty =>
/// "human" (the intended default for an interactive human at a
/// terminal); any non-empty value overrides. Mirrors the
/// `resolve_ai_actor_name` shape from `mcp-server/src/runtime/change_tracking/mod.rs`
/// but defaults to "human" (CLI default) instead of "ai" (MCP default).
fn resolve_cli_actor_name() -> String {
    std::env::var("LORVEX_AGENT_NAME")
        .ok()
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "human".to_string())
}

pub(crate) struct CliChangelogParams<'a> {
    pub operation: &'a str,
    pub entity_type: &'a str,
    pub entity_id: &'a str,
    pub summary: &'a str,
    pub before_json: Option<Value>,
    pub after_json: Option<Value>,
}

pub(crate) struct CliMultiChangelogParams<'a> {
    pub operation: &'a str,
    pub entity_type: &'a str,
    pub entity_ids: &'a [String],
    pub summary: &'a str,
    pub before_json: Option<Value>,
    pub after_json: Option<Value>,
}

struct CliChangelogWriteParams<'a> {
    version: &'a str,
    operation: &'a str,
    entity_type: &'a str,
    entity_id: Option<&'a str>,
    /// Entity IDs for multi-entity ops (full set, including the
    /// single id for length-1 sets). Empty slice for single-entity
    /// ops so `ai_changelog_entities` carries no registry row —
    /// matches the convention the MCP server's
    /// `log_change_and_enqueue_sync` uses (see
    /// `mcp-server/src/runtime/change_tracking/log_change.rs`).
    entity_ids: &'a [String],
    summary: &'a str,
    before_json: Option<&'a Value>,
    after_json: Option<&'a Value>,
}

/// Insert a row into `ai_changelog` for a CLI-originated write.
///
/// CLI writes default to `initiated_by = "human"` and stamp
/// `mcp_tool = "cli"` (issue #2994 M4) so export / activity
/// classifiers can tell CLI rows apart from MCP rows (which carry the
/// actual MCP tool name) and from Tauri-app writes (which never reach
/// `ai_changelog`). When the CLI is invoked by an agent (Claude Code,
/// etc.), set `LORVEX_AGENT_NAME` in the environment and that name
/// will replace `"human"` in `initiated_by`. The `source_device_id`
/// is read from the `sync_checkpoints` table (same device identity
/// used for sync).
///
/// callers thread `before_json` / `after_json` snapshots
/// through so the per-entity Restore/Undo affordance the desktop UI
/// builds on top of `ai_changelog` actually has the data it needs.
/// Mirrors the MCP server's `LogChangeParams` shape:
///   - `create`: `before_json = None`, `after_json = Some(post-row)`
///   - `update`: `before_json = Some(pre-row)`, `after_json = Some(post-row)`
///   - `delete`: `before_json = Some(pre-row)`, `after_json = None`
///   - aggregate / multi-entity ops: both `None` (no per-entity row)
// Issue #3394 Phase 1: the public `log_cli_changelog*` API takes
// `Option<Value>` by value because every one of its 100+ call sites
// builds a fresh `json!(...)` literal at the call boundary — the owned
// value is the natural signature there. The inner helper is the one
// that strictly only needs a borrow, so the borrow conversion happens
// here in the wrapper.
#[allow(clippy::needless_pass_by_value)]
#[cfg(test)]
pub(crate) fn log_cli_changelog(
    conn: &Connection,
    operation: &str,
    entity_type: &str,
    entity_id: &str,
    summary: &str,
    before_json: Option<Value>,
    after_json: Option<Value>,
) -> Result<(), crate::error::CliError> {
    let version = next_hlc_version(conn)?;
    log_cli_changelog_inner(
        conn,
        CliChangelogWriteParams {
            version: &version,
            operation,
            entity_type,
            entity_id: Some(entity_id),
            entity_ids: &[],
            summary,
            before_json: before_json.as_ref(),
            after_json: after_json.as_ref(),
        },
    )
}

/// variant that mints the changelog row's HLC version
/// from a caller-owned `HlcState` guard so the audit row joins the same
/// counter run as the surrounding row write and outbox enqueue.
/// every `log_cli_changelog` call re-locked the process-wide HLC mutex
/// (via the inner `next_hlc_version`) and produced a version that did
/// not share a strict-monotonic ordering with the envelopes the same
/// CLI mutation just enqueued. Hot paths (`complete_habit_with_conn`,
/// `set_task_reminders_with_conn`, every `apply_*` in focus.rs) hold a
/// `lock_shared` guard for their write block; thread it through here so
/// the changelog version sorts deterministically with the row version
/// and the outbox version on every peer.
// See `log_cli_changelog` above — same justification for the
// owned-`Option<Value>` signature on this `_with_state` variant.
#[allow(clippy::needless_pass_by_value)]
pub(crate) fn log_cli_changelog_with_state(
    conn: &Connection,
    hlc_state: &mut HlcState,
    params: CliChangelogParams<'_>,
) -> Result<(), crate::error::CliError> {
    let version = hlc_state.generate().to_string();
    log_cli_changelog_inner(
        conn,
        CliChangelogWriteParams {
            version: &version,
            operation: params.operation,
            entity_type: params.entity_type,
            entity_id: Some(params.entity_id),
            entity_ids: &[],
            summary: params.summary,
            before_json: params.before_json.as_ref(),
            after_json: params.after_json.as_ref(),
        },
    )
}

#[allow(clippy::needless_pass_by_value)]
pub(crate) fn log_cli_changelog_many_with_state(
    conn: &Connection,
    hlc_state: &mut HlcState,
    params: CliMultiChangelogParams<'_>,
) -> Result<(), crate::error::CliError> {
    let version = hlc_state.generate().to_string();
    log_cli_changelog_inner(
        conn,
        CliChangelogWriteParams {
            version: &version,
            operation: params.operation,
            entity_type: params.entity_type,
            entity_id: params.entity_ids.first().map(String::as_str),
            entity_ids: params.entity_ids,
            summary: params.summary,
            before_json: params.before_json.as_ref(),
            after_json: params.after_json.as_ref(),
        },
    )
}

pub(crate) fn execute_cli_mutation_with_finalizer<M, MapStoreError, Finalize>(
    conn: &Connection,
    hlc_state: &mut HlcState,
    mutation: &M,
    map_store_error: MapStoreError,
    finalize: Finalize,
) -> Result<MutationOutput, crate::error::CliError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> crate::error::CliError,
    Finalize: FnOnce(MutationExecution, &mut HlcState) -> Result<(), crate::error::CliError>,
{
    let mut staged_execution: Option<MutationExecution> = None;
    let output = {
        let state: &mut HlcState = hlc_state;
        let handle = CliHlcStateHandle::new(state);
        let session = HlcSession::new(&handle);
        let cx = MutationContext::new(&session);
        execute_with_context(mutation, conn, &cx, map_store_error, |execution| {
            staged_execution = Some(execution);
            Ok(())
        })?
    };
    let execution =
        staged_execution.expect("Mutation contract: execute_with_context staged finalizer payload");
    finalize(execution, hlc_state)?;
    Ok(output)
}

pub(crate) fn execute_cli_entity_mutation_map_store_error<M, MapStoreError>(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    mutation: &M,
    entity_id: &str,
    map_store_error: MapStoreError,
) -> Result<MutationOutput, crate::error::CliError>
where
    M: Mutation,
    MapStoreError: Fn(StoreError) -> crate::error::CliError,
{
    let entity_id = entity_id.to_string();
    execute_cli_mutation_with_finalizer(
        conn,
        hlc_state,
        mutation,
        map_store_error,
        |execution, hlc_state| {
            enqueue_entity_upsert(
                conn,
                execution.entity_kind,
                &entity_id,
                hlc_state,
                device_id,
            )?;
            log_cli_changelog_with_state(
                conn,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &entity_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            lorvex_runtime::bump_local_change_seq(conn)?;
            Ok(())
        },
    )
}

fn log_cli_changelog_inner(
    conn: &Connection,
    params: CliChangelogWriteParams<'_>,
) -> Result<(), crate::error::CliError> {
    // Round-3 audit finding #2: gate the CLI write funnel through the
    // shared rate limiter (`lorvex_runtime::rate_limit`) at the very
    // top of the function so a rejected write emits zero side effects
    // — no HLC stamp, no UUID consumption, no SQL. Mirror the MCP
    // server's `log_change_and_enqueue_sync` shape; both surfaces wrap
    // the same `WriteRateLimitState` math, with INDEPENDENT
    // per-process singletons (separate processes = separate token
    // budgets, by design).
    crate::cli_rate_limit::check_cli_write_rate_limit()?;

    let changelog_id = lorvex_domain::new_entity_id_string();
    let timestamp = lorvex_domain::sync_timestamp_now();
    let device_id = get_or_create_device_id(conn)?;
    let actor = resolve_cli_actor_name();
    // Sanitize the summary at the audit-write boundary so a CLI write
    // carrying user-controlled prose (task titles, list names, memory
    // keys) cannot land control characters or oversized text into
    // `ai_changelog.summary`. The MCP server runs the same defense on
    // its own funnel; routing both surfaces through the shared helper
    // keeps the invariant from drifting between them.
    let sanitized_summary = sanitize_changelog_summary(params.summary);
    let before_json_str = encode_state_json(params.before_json);
    let after_json_str = encode_state_json(params.after_json);
    let should_sync_changelog = !(params.entity_type == ENTITY_PREFERENCE
        && params
            .entity_id
            .is_some_and(lorvex_domain::preference_keys::is_local_only_preference));
    // Delegate to the canonical writer in `lorvex_workflow::
    // changelog`. The CLI surface stamps `undo_token = None` (the
    // CLI does not yet implement the held-outbox-undo flow #2367) and
    // `is_preview = false` (preview rows are an MCP-only `import_data`
    // dry-run affordance). A future schema extension is one struct
    // addition + one prepare_cached statement, not a parallel update.
    lorvex_store::changelog::write_changelog_row(
        conn,
        &lorvex_store::changelog::ChangelogRow {
            id: &changelog_id,
            timestamp: &timestamp,
            operation: params.operation,
            entity_type: params.entity_type,
            entity_id: params.entity_id,
            entity_ids: params.entity_ids,
            summary: &sanitized_summary,
            initiated_by: &actor,
            mcp_tool: Some(CLI_AI_CHANGELOG_TOOL),
            source_device_id: &device_id,
            before_json: before_json_str.as_deref(),
            after_json: after_json_str.as_deref(),
            undo_token: None,
            is_preview: false,
        },
    )?;

    if !should_sync_changelog {
        return Ok(());
    }

    // Enqueue the changelog entry to the sync outbox so it replicates to
    // other devices — mirrors what the MCP server does in
    // `enqueue_changelog_to_outbox`. Single-entity ops stamp
    // `entity_ids = null` so the outbox row matches the local
    // `ai_changelog_entities` shape MCP writes (peers therefore see
    // byte-identical envelopes regardless of which surface produced
    // the change). Multi-entity ops carry the canonical JSON array
    // built directly from the entity-id slice — no intermediate
    // round-trip through a JSON-string column on `ai_changelog`.
    let entity_ids_value: Option<serde_json::Value> = if params.entity_ids.is_empty() {
        None
    } else {
        Some(serde_json::to_value(params.entity_ids)?)
    };
    let payload = json!({
        "id": changelog_id,
        "timestamp": timestamp,
        "operation": params.operation,
        "entity_type": params.entity_type,
        "entity_id": params.entity_id,
        "entity_ids": entity_ids_value,
        // Replicate the sanitized summary (matches what the local
        // `ai_changelog` row carries) so peers see the same scrubbed
        // text that this device persisted — no peer should reconstruct
        // the raw control characters from the outbox payload.
        "summary": sanitized_summary,
        "initiated_by": actor,
        "mcp_tool": CLI_AI_CHANGELOG_TOOL,
        "source_device_id": device_id,
        "before_json": before_json_str,
        "after_json": after_json_str,
        // Schema parity with the MCP outbox builder: every column on
        // `ai_changelog` must round-trip through the envelope. The
        // CLI writer never populates either column today (CLI does
        // not implement the held-outbox-undo flow #2367, and preview
        // rows are an MCP-only `import_data` affordance), but
        // omitting them from the payload would let a peer's apply
        // INSERT silently fall back to schema defaults — and a
        // future schema column would drift here too. Stamp them
        // explicitly.
        "undo_token": serde_json::Value::Null,
        "is_preview": false,
    });
    enqueue_payload_upsert(
        conn,
        ENTITY_AI_CHANGELOG,
        &changelog_id,
        &payload,
        bare_outbox_ctx(params.version, &device_id),
    )?;

    Ok(())
}

/// Build an `OutboxWriteContext` from a version + device id pair —
/// the shape every CLI write uses. Hoisting the construction here
/// removes the field-name boilerplate that obscured the version /
/// device_id at every enqueue call.
pub(crate) const fn bare_outbox_ctx<'a>(
    version: &'a str,
    device_id: &'a str,
) -> OutboxWriteContext<'a> {
    OutboxWriteContext { version, device_id }
}

pub(crate) fn anchored_timezone_name_for_conn(
    conn: &Connection,
) -> Result<String, crate::error::CliError> {
    Ok(lorvex_workflow::timezone::anchored_timezone_name(conn)?)
}

pub(crate) fn today_ymd_for_conn(conn: &Connection) -> Result<String, crate::error::CliError> {
    Ok(lorvex_workflow::timezone::today_ymd_for_conn(conn)?)
}

/// `today_ymd_for_conn` already in `YYYY-MM-DD` form, parsed into a
/// `chrono::NaiveDate`. Centralizes the `parse_from_str` + error-mapping
/// boilerplate that 4 query sites open-coded; the underlying
/// timezone helper guarantees canonical wire format so the parse is
/// infallible in practice but still typed-fallible — propagating as
/// `CliError::Internal` matches the open-coded sites this replaced.
pub(crate) fn today_naivedate_for_conn(
    conn: &Connection,
) -> Result<chrono::NaiveDate, crate::error::CliError> {
    let ymd = today_ymd_for_conn(conn)?;
    chrono::NaiveDate::parse_from_str(&ymd, "%Y-%m-%d")
        .map_err(|e| crate::error::CliError::Internal(format!("failed to parse today date: {e}")))
}

/// Default an optional `YYYY-MM-DD` date arg to "today in the user's
/// timezone" via `today_ymd_for_conn`. Validates the supplied date
/// format when present.
pub(crate) fn resolve_date_or_today(
    conn: &Connection,
    date: Option<&str>,
) -> Result<String, crate::error::CliError> {
    match date {
        Some(date) => {
            lorvex_domain::validation::validate_date_format(date)?;
            Ok(date.to_string())
        }
        None => today_ymd_for_conn(conn),
    }
}

/// Validate that `value` parses as a `YYYY-MM-DD` date string.
/// Used by every `commands::mutate` surface that accepts a calendar-shaped date
/// argument (calendar events, focus schedules, daily reviews, etc.).
pub(crate) fn validate_calendar_date(value: &str) -> Result<(), crate::error::CliError> {
    lorvex_domain::validation::validate_date_format(value).map_err(Into::into)
}

/// Confirm that a task row with `task_id` exists. Used by every
/// surface that links to a task (calendar attendees, daily-review
/// links, etc.) before recording the relationship.
pub(crate) fn ensure_task_exists(
    conn: &Connection,
    task_id: &str,
) -> Result<(), crate::error::CliError> {
    let exists = conn
        .prepare_cached("SELECT 1 FROM tasks WHERE id = ?1")?
        .exists([task_id])?;
    if exists {
        Ok(())
    } else {
        Err(crate::error::CliError::NotFound(format!(
            "task '{task_id}' not found"
        )))
    }
}

pub(crate) fn date_plus_days_ymd_for_conn(
    conn: &Connection,
    offset_days: i64,
) -> Result<String, crate::error::CliError> {
    Ok(lorvex_workflow::timezone::date_plus_days_ymd_for_conn(
        conn,
        offset_days,
    )?)
}

/// `enqueue_payload_upsert` for an aggregate-rooted entity (current_focus,
/// focus_schedule, daily_review). Loads the current row's full aggregate
/// payload (header + child task_ids + computed summaries) and ships it as
/// the upsert envelope.
///
/// Treats a missing row as a hard error: every caller is on the upsert
/// path having just committed the row in the same transaction, so the
/// row must exist by construction. The trash-cascade flow uses the
/// sibling `_locked` variant below, which opts into the
/// missing-row-is-OK semantics explicitly.
pub(crate) fn enqueue_aggregate_root_upsert(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    entity_type: &'static str,
    entity_id: &str,
) -> Result<(), crate::error::CliError> {
    debug_assert!(
        lorvex_domain::naming::EntityKind::parse(entity_type).is_some_and(
            lorvex_sync::payload_build::aggregate::kind_is_aggregate_root_with_embedded_children
        ),
        "enqueue_aggregate_root_upsert called with non-aggregate type {entity_type:?}"
    );
    // The "row vanished" branch is a hard error here: every caller
    // is on the upsert path having just committed the row in the
    // same transaction. The mirror `_locked` variant below covers
    // the trash-cascade scenario where the row may already have
    // been swept by a sibling cascade — that helper opts into the
    // missing-row-is-OK semantics explicitly.
    let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        entity_type,
        entity_id,
    )?
    else {
        return Err(crate::error::CliError::Internal(format!(
            "{entity_type} '{entity_id}' enqueue: row vanished between persist and enqueue"
        )));
    };
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}

#[cfg(test)]
mod tests;
