//! Daily review write entry points: `add` and `amend`.
//!
//! Both run inside an immediate transaction, validate the link sets
//! against `tasks` and `lists`, persist via `lorvex_workflow`,
//! re-load the canonical view, enqueue an outbox upsert, and write a
//! changelog entry. Returning the freshly-loaded `DailyReviewView`
//! preserves the rich-return-value contract the MCP server enforces.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::daily_view::load_daily_review_view_for_date;
use super::links_validation::{validate_review_list_links, validate_review_task_links};
use super::sync_outbox::enqueue_daily_review_payload_upsert;
use super::validation::{
    normalize_review_link_ids, sanitize_daily_review_optional_text,
    sanitize_daily_review_required_text, validate_daily_review_scale,
};
use crate::commands::shared::effects::resolve_date_or_today;
use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;
use crate::models::DailyReviewView;

struct AddCliDailyReviewMutation<'a> {
    date: &'a str,
    summary: &'a str,
    mood: Option<i64>,
    energy_level: Option<i64>,
    wins: Option<&'a str>,
    blockers: Option<&'a str>,
    learnings: Option<&'a str>,
    ai_synthesis: Option<&'a str>,
    linked_task_ids: &'a [String],
    linked_list_ids: &'a [String],
    timezone: &'a str,
    now: &'a str,
    operation: &'static str,
    before: Option<Value>,
}

impl<'a> Mutation for AddCliDailyReviewMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_DAILY_REVIEW
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let applied = lorvex_store::daily_review_ops::upsert_daily_review(
            conn,
            &lorvex_store::daily_review_ops::UpsertDailyReviewParams {
                date: self.date,
                summary: self.summary,
                mood: self.mood,
                energy_level: self.energy_level,
                wins: self.wins,
                blockers: self.blockers,
                learnings: self.learnings,
                ai_synthesis: self.ai_synthesis,
                timezone: self.timezone,
                version: &version,
                now: self.now,
            },
        )?;
        lorvex_store::daily_review_ops::require_daily_review_write_applied(applied, self.date)?;
        lorvex_store::daily_review_ops::materialize_review_task_links(
            conn,
            self.date,
            self.linked_task_ids,
        )?;
        lorvex_store::daily_review_ops::materialize_review_list_links(
            conn,
            self.date,
            self.linked_list_ids,
        )?;

        let review = lorvex_store::daily_review_ops::get_daily_review_row(conn, self.date)?
            .ok_or_else(|| {
                StoreError::Invariant(format!("daily review '{}' vanished after write", self.date))
            })?;
        Ok(MutationOutput::new(
            serde_json::to_value(review)?,
            format!(
                "Daily review {} for {}",
                if self.operation == "update" {
                    "updated"
                } else {
                    "added"
                },
                self.date
            ),
        ))
    }
}

struct AmendCliDailyReviewMutation<'a> {
    date: &'a str,
    summary: Option<&'a str>,
    mood: Option<i64>,
    energy_level: Option<i64>,
    wins: Option<&'a str>,
    blockers: Option<&'a str>,
    learnings: Option<&'a str>,
    ai_synthesis: Option<&'a str>,
    linked_task_ids: Option<&'a [String]>,
    linked_list_ids: Option<&'a [String]>,
    timezone_backfill: Option<&'a str>,
    now: &'a str,
    before: Value,
}

impl<'a> Mutation for AmendCliDailyReviewMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_DAILY_REVIEW
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let applied = lorvex_store::daily_review_ops::amend_daily_review(
            conn,
            &lorvex_store::daily_review_ops::AmendDailyReviewParams {
                date: self.date,
                summary: self.summary,
                mood: self.mood,
                energy_level: self.energy_level,
                wins: self.wins,
                blockers: self.blockers,
                learnings: self.learnings,
                ai_synthesis: self.ai_synthesis,
                timezone_backfill: self.timezone_backfill,
                version: &version,
                now: self.now,
            },
        )?;
        lorvex_store::daily_review_ops::require_daily_review_write_applied(applied, self.date)?;
        if let Some(task_ids) = self.linked_task_ids {
            lorvex_store::daily_review_ops::materialize_review_task_links(
                conn, self.date, task_ids,
            )?;
        }
        if let Some(list_ids) = self.linked_list_ids {
            lorvex_store::daily_review_ops::materialize_review_list_links(
                conn, self.date, list_ids,
            )?;
        }

        let review = lorvex_store::daily_review_ops::get_daily_review_row(conn, self.date)?
            .ok_or_else(|| {
                StoreError::Invariant(format!("daily review '{}' vanished after amend", self.date))
            })?;
        Ok(MutationOutput::new(
            serde_json::to_value(review)?,
            format!("Daily review amended for {}", self.date),
        ))
    }
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct DailyReviewAddFields<'a> {
    pub(crate) date: Option<&'a str>,
    pub(crate) summary: &'a str,
    pub(crate) mood: Option<u8>,
    pub(crate) energy_level: Option<u8>,
    pub(crate) wins: Option<&'a str>,
    pub(crate) blockers: Option<&'a str>,
    pub(crate) learnings: Option<&'a str>,
    pub(crate) ai_synthesis: Option<&'a str>,
    pub(crate) linked_task_ids: &'a [String],
    pub(crate) linked_list_ids: &'a [String],
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct DailyReviewAmendFields<'a> {
    pub(crate) date: &'a str,
    pub(crate) summary: Option<&'a str>,
    pub(crate) mood: Option<u8>,
    pub(crate) energy_level: Option<u8>,
    pub(crate) wins: Option<&'a str>,
    pub(crate) blockers: Option<&'a str>,
    pub(crate) learnings: Option<&'a str>,
    pub(crate) ai_synthesis: Option<&'a str>,
    pub(crate) linked_task_ids: Option<&'a [String]>,
    pub(crate) linked_list_ids: Option<&'a [String]>,
}

pub(crate) fn add_daily_review_with_conn(
    conn: &mut Connection,
    fields: DailyReviewAddFields<'_>,
) -> Result<DailyReviewView, crate::error::CliError> {
    validate_daily_review_scale("mood", fields.mood)?;
    validate_daily_review_scale("energy", fields.energy_level)?;
    let summary = sanitize_daily_review_required_text("summary", fields.summary)?;
    let wins = sanitize_daily_review_optional_text("wins", fields.wins)?;
    let blockers = sanitize_daily_review_optional_text("blockers", fields.blockers)?;
    let learnings = sanitize_daily_review_optional_text("learnings", fields.learnings)?;
    let ai_synthesis = sanitize_daily_review_optional_text("ai_synthesis", fields.ai_synthesis)?;
    let linked_task_ids = normalize_review_link_ids("linked_task_ids", fields.linked_task_ids)?;
    let linked_list_ids = normalize_review_link_ids("linked_list_ids", fields.linked_list_ids)?;

    let device_id = get_or_create_device_id(conn)?;
    let today = resolve_date_or_today(conn, None)?;
    let date =
        lorvex_workflow::daily_review_date::resolve_daily_review_write_date(fields.date, &today)
            .map_err(|error| crate::error::CliError::Validation(error.to_string()))?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    validate_review_task_links(&tx, &linked_task_ids)?;
    validate_review_list_links(&tx, &linked_list_ids)?;

    // keep the pre-mutation review row for the audit
    // trail (was discarded — only `existed` was inspected).
    let before_review = load_daily_review_view_for_date(&tx, &date)?;
    let existed = before_review.is_some();
    let timezone = lorvex_workflow::timezone::active_timezone_name(&tx)?.unwrap_or_else(|| {
        lorvex_workflow::timezone::anchored_timezone_name(&tx).unwrap_or_else(|_| "UTC".to_string())
    });
    let operation = if existed { "update" } else { "create" };
    let before_json = before_review
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = AddCliDailyReviewMutation {
        date: &date,
        summary: &summary,
        mood: fields.mood.map(i64::from),
        energy_level: fields.energy_level.map(i64::from),
        wins: wins.as_deref(),
        blockers: blockers.as_deref(),
        learnings: learnings.as_deref(),
        ai_synthesis: ai_synthesis.as_deref(),
        linked_task_ids: &linked_task_ids,
        linked_list_ids: &linked_list_ids,
        timezone: &timezone,
        now: &now,
        operation,
        before: before_json,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let mut after_review: Option<DailyReviewView> = None;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let review = load_daily_review_view_for_date(&tx, &date)?.ok_or_else(|| {
                crate::error::CliError::NotFound(format!(
                    "daily review '{date}' not found after write"
                ))
            })?;
            enqueue_daily_review_payload_upsert(&tx, hlc_state, &device_id, &review)?;
            let after_json = Some(serde_json::to_value(&review)?);
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &date,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json,
                },
            )?;
            bump_local_change_seq(&tx)?;
            after_review = Some(review);
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(after_review.expect("daily review add finalizer should load post-state"))
}

pub(crate) fn amend_daily_review_with_conn(
    conn: &mut Connection,
    fields: DailyReviewAmendFields<'_>,
) -> Result<DailyReviewView, crate::error::CliError> {
    let today = resolve_date_or_today(conn, None)?;
    let date = lorvex_workflow::daily_review_date::resolve_daily_review_write_date(
        Some(fields.date),
        &today,
    )
    .map_err(|error| crate::error::CliError::Validation(error.to_string()))?;
    validate_daily_review_scale("mood", fields.mood)?;
    validate_daily_review_scale("energy", fields.energy_level)?;
    let summary = fields
        .summary
        .map(|value| sanitize_daily_review_required_text("summary", value))
        .transpose()?;
    let wins = sanitize_daily_review_optional_text("wins", fields.wins)?;
    let blockers = sanitize_daily_review_optional_text("blockers", fields.blockers)?;
    let learnings = sanitize_daily_review_optional_text("learnings", fields.learnings)?;
    let ai_synthesis = sanitize_daily_review_optional_text("ai_synthesis", fields.ai_synthesis)?;
    let linked_task_ids = fields
        .linked_task_ids
        .map(|ids| normalize_review_link_ids("linked_task_ids", ids))
        .transpose()?;
    let linked_list_ids = fields
        .linked_list_ids
        .map(|ids| normalize_review_link_ids("linked_list_ids", ids))
        .transpose()?;

    if summary.is_none()
        && fields.mood.is_none()
        && fields.energy_level.is_none()
        && wins.is_none()
        && blockers.is_none()
        && learnings.is_none()
        && ai_synthesis.is_none()
        && linked_task_ids.is_none()
        && linked_list_ids.is_none()
    {
        return Err(crate::error::CliError::Validation(
            "review amend requires at least one field or link set".to_string(),
        ));
    }

    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = load_daily_review_view_for_date(&tx, &date)?.ok_or_else(|| {
        crate::error::CliError::NotFound(format!("no review found for date '{date}'"))
    })?;
    if let Some(task_ids) = linked_task_ids.as_ref() {
        validate_review_task_links(&tx, task_ids)?;
    }
    if let Some(list_ids) = linked_list_ids.as_ref() {
        validate_review_list_links(&tx, list_ids)?;
    }

    let timezone_backfill = before.timezone.is_none().then(|| {
        lorvex_workflow::timezone::anchored_timezone_name(&tx).unwrap_or_else(|_| "UTC".to_string())
    });
    let before_value = serde_json::to_value(&before)?;
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = AmendCliDailyReviewMutation {
        date: &date,
        summary: summary.as_deref(),
        mood: fields.mood.map(i64::from),
        energy_level: fields.energy_level.map(i64::from),
        wins: wins.as_deref(),
        blockers: blockers.as_deref(),
        learnings: learnings.as_deref(),
        ai_synthesis: ai_synthesis.as_deref(),
        linked_task_ids: linked_task_ids.as_deref(),
        linked_list_ids: linked_list_ids.as_deref(),
        timezone_backfill: timezone_backfill.as_deref(),
        now: &now,
        before: before_value,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let mut after_review: Option<DailyReviewView> = None;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let review = load_daily_review_view_for_date(&tx, &date)?.ok_or_else(|| {
                crate::error::CliError::NotFound(format!(
                    "daily review '{date}' not found after amend"
                ))
            })?;
            enqueue_daily_review_payload_upsert(&tx, hlc_state, &device_id, &review)?;
            let after_json = Some(serde_json::to_value(&review)?);
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &date,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json,
                },
            )?;
            bump_local_change_seq(&tx)?;
            after_review = Some(review);
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(after_review.expect("daily review amend finalizer should load post-state"))
}
