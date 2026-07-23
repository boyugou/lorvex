use super::validate_review_scales;
use crate::contract::{AmendDailyReviewArgs, MAX_AI_NOTES_LENGTH, MAX_LONG_TEXT_LENGTH};
use crate::contract_validate::{ContractValidate, ValidationCtx};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::utc_now_iso;
use crate::tasks::validation::validate_optional_string_length;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::timezone::{anchored_timezone_name, today_ymd_for_conn};
use rusqlite::Connection;
use serde_json::Value;

struct AmendDailyReviewMutation<'a> {
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

impl<'a> Mutation for AmendDailyReviewMutation<'a> {
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

        let updated = lorvex_store::daily_review_ops::get_daily_review_row(conn, self.date)?
            .ok_or_else(|| {
                StoreError::Invariant(format!("daily review '{}' vanished after amend", self.date))
            })?;
        let after = serde_json::to_value(updated)?;

        Ok(MutationOutput::new(
            after,
            format!("Daily review amended for {}", self.date),
        ))
    }
}

pub(crate) fn amend_daily_review(
    conn: &Connection,
    args: AmendDailyReviewArgs,
) -> Result<String, McpError> {
    // validate linked_task_ids / linked_list_ids exist (and that
    // task_ids reference live, non-archived rows) at the trust
    // boundary via the `ContractValidate` derive. The previous
    // hand-rolled gate ran AFTER the daily-review header upsert,
    // so a phantom ID still bumped the parent row before failing —
    // the derive lifts the check ahead of the write so the amend
    // is fully transactional with respect to its inputs.
    args.validate(&ValidationCtx::new(conn))?;
    let AmendDailyReviewArgs {
        date,
        summary,
        mood,
        energy_level,
        wins,
        blockers,
        learnings,
        ai_synthesis,
        linked_task_ids,
        linked_list_ids,
    } = args;

    validate_review_scales(mood, energy_level)?;
    let today = today_ymd_for_conn(conn)?;
    let date =
        lorvex_workflow::daily_review_date::resolve_daily_review_write_date(Some(&date), &today)
            .map_err(|error| McpError::Validation(error.to_string()))?;
    // parity with the add path — scrub free-text
    // fields through `sanitize_user_text` BEFORE length validation.
    let summary = summary.map(|s| lorvex_domain::sanitize_user_text(&s));
    let wins = wins.map(|s| lorvex_domain::sanitize_user_text(&s));
    let blockers = blockers.map(|s| lorvex_domain::sanitize_user_text(&s));
    let learnings = learnings.map(|s| lorvex_domain::sanitize_user_text(&s));
    let ai_synthesis = ai_synthesis.map(|s| lorvex_domain::sanitize_user_text(&s));
    validate_optional_string_length(summary.as_deref(), "summary", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(wins.as_deref(), "wins", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(blockers.as_deref(), "blockers", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(learnings.as_deref(), "learnings", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(ai_synthesis.as_deref(), "ai_synthesis", MAX_AI_NOTES_LENGTH)?;

    let before = lorvex_store::daily_review_ops::get_daily_review_row(conn, &date)?
        .map(serde_json::to_value)
        .transpose()?;
    if before.is_none() {
        return Err(McpError::NotFound(format!(
            "No review found for date '{date}'"
        )));
    }

    let now = utc_now_iso();

    let existing_timezone = before
        .as_ref()
        .and_then(|row| row.get("timezone"))
        .and_then(Value::as_str)
        .map(str::to_string);
    let tz_backfill = if existing_timezone.is_none() {
        Some(anchored_timezone_name(conn)?)
    } else {
        None
    };

    let mutation = AmendDailyReviewMutation {
        date: date.as_str(),
        summary: summary.as_deref(),
        mood: mood.map(i64::from),
        energy_level: energy_level.map(i64::from),
        wins: wins.as_deref(),
        blockers: blockers.as_deref(),
        learnings: learnings.as_deref(),
        ai_synthesis: ai_synthesis.as_deref(),
        linked_task_ids: linked_task_ids.as_deref(),
        linked_list_ids: linked_list_ids.as_deref(),
        timezone_backfill: tz_backfill.as_deref(),
        now: now.as_str(),
        before: before.expect("daily review existence checked before mutation"),
    };
    let output = execute_mcp_mutation(conn, &mutation, "amend_daily_review", date.as_str())?;

    Ok(serde_json::to_string(&output.after)?)
}
