//! Calendar subscription CRUD and refresh from the CLI.
//!
//! Wires the workflow's calendar_subscription mutation descriptors
//! (`AddCalendarSubscriptionMutation`, `RemoveCalendarSubscriptionMutation`,
//! `ToggleCalendarSubscriptionMutation`) into the CLI mutation
//! executor, then ships the freshly-written payload to the sync outbox
//! through `enqueue_payload_upsert` / `enqueue_payload_delete`. The
//! refresh path drives the workflow orchestrator
//! ([`lorvex_workflow::calendar_subscription::sync_calendar_subscription`])
//! against a `reqwest::blocking`-backed `FetchBackend` so a CLI user
//! can poll a feed without bringing up the Tauri app.
//!
//! Output formatting mirrors the lists CLI surface: human-readable
//! text by default, canonical mutation/query envelopes under
//! `--format json` so a shell pipeline can parse the typed payload.

use std::time::Duration;

use lorvex_domain::naming::{ENTITY_CALENDAR_SUBSCRIPTION, OP_DELETE, OP_UPSERT};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id, resolve_db_path};
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use lorvex_workflow::calendar_subscription::tzid::noop_unknown_tzid_sink;
use lorvex_workflow::calendar_subscription::validation::{
    sanitize_url_for_display, validate_ics_url_safety, DefaultHostResolver,
};
use lorvex_workflow::calendar_subscription::{
    list_calendar_subscriptions as workflow_list_calendar_subscriptions,
    remove_payload_was_present,
    sync_all_calendar_subscriptions as workflow_sync_all_calendar_subscriptions,
    sync_calendar_subscription as workflow_sync_calendar_subscription, upsert_payload_matched,
    AddCalendarSubscriptionMutation, CalendarSubscription, FetchBackend, FetchedIcs,
    FetchedIcsError, RemoveCalendarSubscriptionMutation, SubscriptionSyncResult,
    ToggleCalendarSubscriptionMutation,
};
use lorvex_workflow::mutation::MutationExecution;
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::cli::OutputFormat;
use crate::commands::shared::effects::execute_cli_mutation_with_finalizer;
use crate::commands::shared::{
    bare_outbox_ctx, log_cli_changelog_with_state, render_mutation_envelope, render_query_envelope,
    CliChangelogParams,
};
use crate::error::CliError;
use crate::hlc_guard::lock_shared;
use crate::startup_maintenance::open_db_at_path;

/// `reqwest::blocking`-backed [`FetchBackend`] used by the CLI's
/// `subscription refresh` arms. Re-uses the workflow's
/// URL safety / SSRF validation (`validate_ics_url_safety`) but skips
/// the Tauri-only DNS-rebinding pin + idle-timeout reader — the CLI
/// is a one-shot CLI process, not a long-running app surface, so the
/// `reqwest::blocking::Client` defaults (with explicit total/connect
/// timeouts) are the right shape here.
struct CliFetchBackend;

impl CliFetchBackend {
    fn build_client() -> Result<reqwest::blocking::Client, FetchedIcsError> {
        reqwest::blocking::Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .user_agent(concat!(
                "Lorvex-CLI/",
                env!("CARGO_PKG_VERSION"),
                " (+https://github.com/boyugou/ai-native-todo) Calendar Subscription"
            ))
            .build()
            .map_err(|e| FetchedIcsError::Other(format!("failed to build HTTP client: {e}")))
    }
}

impl FetchBackend for CliFetchBackend {
    fn fetch_ics(&self, url: &str, _etag: Option<&str>) -> Result<FetchedIcs, FetchedIcsError> {
        let safe_url = sanitize_url_for_display(url);
        let parsed = reqwest::Url::parse(url).map_err(|e| {
            FetchedIcsError::Other(format!("invalid subscription URL {safe_url}: {e}"))
        })?;
        // SSRF / scheme / private-IP defenses share the workflow's
        // resolver path — exact same denylist the Tauri surface
        // applies. CLI does not pin resolved addresses onto the
        // client (DNS-rebinding pinning is a long-running-process
        // hardening; the CLI's one-shot lifetime makes the window
        // negligible), but the validation is still load-bearing.
        validate_ics_url_safety(&parsed, &DefaultHostResolver)
            .map_err(|e| FetchedIcsError::Other(format!("rejected subscription URL: {e}")))?;

        let client = Self::build_client()?;
        let response = client.get(parsed).send().map_err(|e| {
            FetchedIcsError::Other(format!("HTTP fetch failed for {safe_url}: {e}"))
        })?;

        let status = response.status();
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            let retry_after_secs = response
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.trim().parse::<u64>().ok());
            return Err(FetchedIcsError::RateLimited {
                retry_after_secs,
                safe_url,
            });
        }
        if !status.is_success() {
            return Err(FetchedIcsError::Other(format!("HTTP {status}: {safe_url}")));
        }

        let body = response
            .text()
            .map_err(|e| FetchedIcsError::Other(format!("failed to read body: {e}")))?;
        // truncation detection mirrors the Tauri fetch flow — a
        // mid-stream cut-off must surface as `Truncated` so the
        // orchestrator preserves the cached events on the next
        // refresh.
        if let Err(reason) =
            lorvex_workflow::calendar_subscription::truncation::detect_ics_truncation(&body)
        {
            return Err(FetchedIcsError::Truncated { reason, safe_url });
        }
        Ok(FetchedIcs {
            body,
            etag: None,
            status: status.as_u16(),
        })
    }
}

// ── list ───────────────────────────────────────────────────────────

pub(crate) fn run_subscription_list(
    format: OutputFormat,
    verbose: bool,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let rows = workflow_list_calendar_subscriptions(&conn)
        .map_err(|e| CliError::Internal(e.to_string()))?;
    match format {
        OutputFormat::Text => Ok(render_subscriptions_text(&rows, verbose)),
        // JSON output always emits the full row shape; the `--verbose`
        // flag is a text-renderer concern and would otherwise be a
        // confusing degree of freedom on a machine-readable surface.
        OutputFormat::Json => render_query_envelope(
            "query.subscriptions.list",
            &db_path,
            json!({ "subscriptions": rows }),
        ),
    }
}

/// Format an RFC3339 timestamp as a coarse "Nm ago" / "Nh ago" / "Nd ago"
/// label, anchored at the current system clock. Falls back to the raw
/// timestamp if parsing fails so we never lose information.
///
/// Coarse-only on purpose: the compact subscription listing wants
/// "scannable at a glance," and the underlying timestamp is in the
/// JSON output for callers that need precision.
fn format_relative_ago(now: chrono::DateTime<chrono::Utc>, raw: &str) -> String {
    let Ok(then) = chrono::DateTime::parse_from_rfc3339(raw) else {
        return raw.to_string();
    };
    let delta = now.signed_duration_since(then.with_timezone(&chrono::Utc));
    let secs = delta.num_seconds();
    if secs < 0 {
        // Clock skew or a freshly-bumped future timestamp; render
        // raw rather than "in N minutes" — that vocabulary belongs
        // to a different UX surface.
        return raw.to_string();
    }
    if secs < 60 {
        return "just now".to_string();
    }
    let minutes = secs / 60;
    if minutes < 60 {
        return format!("{minutes}m ago");
    }
    let hours = minutes / 60;
    if hours < 24 {
        return format!("{hours}h ago");
    }
    let days = hours / 24;
    if days < 30 {
        return format!("{days}d ago");
    }
    let months = days / 30;
    if months < 12 {
        return format!("{months}mo ago");
    }
    format!("{}y ago", months / 12)
}

/// Per-row status label. Three tiers, ordered by what the operator
/// most wants to act on: an explicit fetch error wins, then the
/// disabled flag, then the workflow's sync_health value (which
/// captures green/degraded/red post-fetch).
fn status_label(sub: &CalendarSubscription) -> String {
    if sub.error_message.is_some() {
        return "error".to_string();
    }
    if !sub.enabled {
        return "disabled".to_string();
    }
    format!("{:?}", sub.sync_health).to_lowercase()
}

fn render_subscriptions_text(rows: &[CalendarSubscription], verbose: bool) -> String {
    if rows.is_empty() {
        return "No calendar subscriptions.\n".to_string();
    }
    let mut out = String::new();
    out.push_str(&format!("{} subscription(s):\n", rows.len()));
    let now = chrono::Utc::now();
    for sub in rows {
        // Compact (default) and verbose share the same identifying
        // top line — feed_url, name, status, refreshed_ago — so the
        // verbose mode is strictly additive. The compact line drops
        // the id from the lead (it's in JSON output for scripts) and
        // surfaces the URL last where it can wrap without breaking
        // column alignment.
        let refreshed = sub
            .last_fetched_at
            .as_deref()
            .map(|raw| format_relative_ago(now, raw))
            .unwrap_or_else(|| "never".to_string());
        out.push_str(&format!(
            "  {name}  [{status}]  refreshed {refreshed}  {url}\n",
            name = sub.name,
            status = status_label(sub),
            refreshed = refreshed,
            url = sub.url,
        ));
        if !verbose {
            continue;
        }
        // Verbose: surface the columns the compact view trims.
        out.push_str(&format!("    id: {}\n", sub.id));
        if let Some(last) = &sub.last_fetched_at {
            out.push_str(&format!("    last_fetched_at: {last}\n"));
        }
        if let Some(err) = &sub.error_message {
            out.push_str(&format!("    last_error: {err}\n"));
        }
        if let Some(next) = &sub.next_retry_at {
            out.push_str(&format!(
                "    next_retry_at: {next}  ({} consecutive failure(s))\n",
                sub.consecutive_failures
            ));
        }
        if let Some(color) = &sub.color {
            out.push_str(&format!("    color: {color}\n"));
        }
    }
    out
}

// ── add ────────────────────────────────────────────────────────────

pub(crate) fn run_subscription_add(
    name: Option<&str>,
    url: &str,
    color: Option<&str>,
    format: OutputFormat,
) -> Result<String, CliError> {
    // Validate the URL ahead of the mutation so a bad input fails
    // before the HLC stamp is consumed. Matches the discipline used
    // for `list create` (validate user-prose before allocating an
    // entity id).
    let parsed = reqwest::Url::parse(url)
        .map_err(|e| CliError::Validation(format!("invalid URL `{url}`: {e}")))?;
    validate_ics_url_safety(&parsed, &DefaultHostResolver)
        .map_err(|e| CliError::Validation(e.to_string()))?;

    let resolved_name = name
        .map(str::to_string)
        .unwrap_or_else(|| sanitize_url_for_display(url));
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let row = add_subscription_with_conn(&mut conn, &resolved_name, url, color)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Added subscription {id} `{name}` -> {url}\n",
            id = row.id,
            name = row.name,
            url = row.url
        )),
        OutputFormat::Json => {
            render_mutation_envelope("subscription.add", &db_path, json!({ "subscription": row }))
        }
    }
}

fn add_subscription_with_conn(
    conn: &mut Connection,
    name: &str,
    url: &str,
    color: Option<&str>,
) -> Result<CalendarSubscription, CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let mutation = AddCalendarSubscriptionMutation::new(
        name.to_string(),
        url.to_string(),
        color.map(str::to_string),
    );
    let id = mutation.id().to_string();
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        CliError::from,
        |execution, hlc_state| {
            enqueue_subscription_payload_cli(&tx, &id, &execution, &device_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let row = workflow_list_calendar_subscriptions(&tx)
        .map_err(|e| CliError::Internal(e.to_string()))?
        .into_iter()
        .find(|s| s.id == id)
        .ok_or_else(|| {
            CliError::NotFound(format!("calendar_subscription '{id}' not found after add"))
        })?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(row)
}

// ── remove ─────────────────────────────────────────────────────────

pub(crate) fn run_subscription_remove(id: &str, format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let removed = remove_subscription_with_conn(&mut conn, id)?;
    match format {
        OutputFormat::Text => Ok(format!("Removed subscription {id}\n")),
        OutputFormat::Json => render_mutation_envelope(
            "subscription.remove",
            &db_path,
            json!({ "removed_id": id, "matched": removed }),
        ),
    }
}

fn remove_subscription_with_conn(conn: &mut Connection, id: &str) -> Result<bool, CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let mutation = RemoveCalendarSubscriptionMutation::new(id.to_string());
    let mut matched = false;
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        CliError::from,
        |execution, hlc_state| {
            if !remove_payload_was_present(&execution.output.after) {
                // tombstone for a row that never existed — keep
                // silent. Matches the Tauri adapter's behaviour.
                return Ok(());
            }
            matched = true;
            enqueue_subscription_payload_cli(&tx, id, &execution, &device_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(matched)
}

// ── toggle ─────────────────────────────────────────────────────────

pub(crate) fn run_subscription_toggle(id: &str, format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let row = workflow_list_calendar_subscriptions(&conn)
        .map_err(|e| CliError::Internal(e.to_string()))?
        .into_iter()
        .find(|s| s.id == id)
        .ok_or_else(|| CliError::NotFound(format!("calendar_subscription '{id}' not found")))?;
    let new_enabled = !row.enabled;
    toggle_subscription_with_conn(&mut conn, id, new_enabled)?;
    match format {
        OutputFormat::Text => Ok(format!(
            "Subscription {id} -> {}\n",
            if new_enabled { "enabled" } else { "disabled" }
        )),
        OutputFormat::Json => render_mutation_envelope(
            "subscription.toggle",
            &db_path,
            json!({ "id": id, "enabled": new_enabled }),
        ),
    }
}

fn toggle_subscription_with_conn(
    conn: &mut Connection,
    id: &str,
    enabled: bool,
) -> Result<(), CliError> {
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let mutation = ToggleCalendarSubscriptionMutation::new(id.to_string(), enabled);
    let mut hlc_guard = lock_shared(&tx)?;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        CliError::from,
        |execution, hlc_state| {
            if !upsert_payload_matched(&execution.output.after) {
                return Ok(());
            }
            enqueue_subscription_payload_cli(&tx, id, &execution, &device_id)?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(execution.output.after),
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(())
}

// ── refresh ────────────────────────────────────────────────────────

pub(crate) fn run_subscription_refresh(
    id: Option<&str>,
    all: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let backend = CliFetchBackend;

    let results: Vec<SubscriptionSyncResult> = if all {
        workflow_sync_all_calendar_subscriptions(&conn, &backend, &noop_unknown_tzid_sink)
            .map_err(|e| CliError::Internal(e.to_string()))?
    } else {
        let Some(id) = id else {
            return Err(CliError::Validation(
                "refresh requires either an id or --all".to_string(),
            ));
        };
        vec![
            workflow_sync_calendar_subscription(&conn, &backend, &noop_unknown_tzid_sink, id)
                .map_err(|e| CliError::Internal(e.to_string()))?,
        ]
    };

    match format {
        OutputFormat::Text => Ok(render_refresh_results_text(&results)),
        OutputFormat::Json => render_mutation_envelope(
            "subscription.refresh",
            &db_path,
            json!({ "results": results }),
        ),
    }
}

fn render_refresh_results_text(results: &[SubscriptionSyncResult]) -> String {
    if results.is_empty() {
        return "No subscriptions refreshed.\n".to_string();
    }
    let mut out = String::new();
    for r in results {
        out.push_str(&format!(
            "  {id}  `{name}`  imported={imp} updated={upd} removed={rem}\n",
            id = r.subscription_id,
            name = r.subscription_name,
            imp = r.events_imported,
            upd = r.events_updated,
            rem = r.events_removed,
        ));
        if let Some(err) = &r.error {
            out.push_str(&format!("    error: {err}\n"));
        }
    }
    out
}

// ── shared outbox enqueue helper ──────────────────────────────────

/// Ship the freshly-written subscription payload to the sync outbox.
/// Mirrors the Tauri-side `enqueue_subscription_payload` — reads the
/// operation and version off the staged [`MutationExecution`] and
/// builds the canonical envelope through the
/// `lorvex_sync::outbox_enqueue` primitives. Suppressed when the
/// `_with_conn` finalizer already short-circuited the no-op path
/// (e.g. delete-of-vanished, toggle-of-vanished); see each handler's
/// `if !upsert_payload_matched / if !remove_payload_was_present`
/// gate above.
fn enqueue_subscription_payload_cli(
    conn: &Connection,
    id: &str,
    execution: &MutationExecution,
    device_id: &str,
) -> Result<(), CliError> {
    let version = execution
        .output
        .after
        .get("version")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            CliError::Internal(format!(
                "calendar_subscription '{id}' apply produced payload without 'version'"
            ))
        })?;
    let ctx = bare_outbox_ctx(version, device_id);
    let payload = &execution.output.after;
    if execution.operation == OP_DELETE {
        enqueue_payload_delete(conn, ENTITY_CALENDAR_SUBSCRIPTION, id, payload, ctx)?;
    } else {
        debug_assert_eq!(execution.operation, OP_UPSERT);
        enqueue_payload_upsert(conn, ENTITY_CALENDAR_SUBSCRIPTION, id, payload, ctx)?;
    }
    Ok(())
}
