use super::validate_review_scales;
use crate::contract::{AddDailyReviewArgs, MAX_AI_NOTES_LENGTH, MAX_LONG_TEXT_LENGTH};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::utc_now_iso;
use crate::tasks::validation::{
    validate_list_ids_exist, validate_optional_string_length, validate_string_length,
    validate_task_ids_active,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::timezone::{anchored_timezone_name, today_ymd_for_conn};
use rusqlite::Connection;
use serde_json::Value;

struct AddDailyReviewMutation<'a> {
    date: &'a str,
    summary: &'a str,
    mood: Option<i64>,
    energy_level: Option<i64>,
    linked_task_ids: Option<&'a [String]>,
    linked_list_ids: Option<&'a [String]>,
    wins: Option<&'a str>,
    blockers: Option<&'a str>,
    learnings: Option<&'a str>,
    ai_synthesis: Option<&'a str>,
    timezone: &'a str,
    now: &'a str,
    operation: &'static str,
    before: Option<Value>,
}

impl<'a> Mutation for AddDailyReviewMutation<'a> {
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

        let row = lorvex_store::daily_review_ops::get_daily_review_row(conn, self.date)?
            .ok_or_else(|| {
                StoreError::Invariant(format!("daily review '{}' vanished after add", self.date))
            })?;
        let after = serde_json::to_value(row)?;
        let summary = format!(
            "Daily review {} for {}",
            if self.operation == "update" {
                "updated"
            } else {
                "added"
            },
            self.date
        );

        Ok(MutationOutput::new(after, summary))
    }
}

pub(crate) fn add_daily_review(
    conn: &Connection,
    args: AddDailyReviewArgs,
) -> Result<String, McpError> {
    let AddDailyReviewArgs {
        date,
        summary,
        mood,
        energy_level,
        linked_task_ids,
        linked_list_ids,
        wins,
        blockers,
        learnings,
        ai_synthesis,
    } = args;

    validate_review_scales(mood, energy_level)?;
    // scrub free-text fields BEFORE the length
    // check.
    // through `sanitize_user_text`, so RLO/ZWSP/C0/C1/LSEP could
    // land verbatim in `daily_reviews.{summary,wins,blockers,…}`
    // and propagate via sync to every peer. Daily-review entries
    // surface in narrative views, where bidi spoofing is the most
    // visible attack — fix at the trust boundary.
    let summary = lorvex_domain::sanitize_user_text(&summary);
    let wins = wins.map(|s| lorvex_domain::sanitize_user_text(&s));
    let blockers = blockers.map(|s| lorvex_domain::sanitize_user_text(&s));
    let learnings = learnings.map(|s| lorvex_domain::sanitize_user_text(&s));
    let ai_synthesis = ai_synthesis.map(|s| lorvex_domain::sanitize_user_text(&s));
    validate_string_length(&summary, "summary", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(wins.as_deref(), "wins", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(blockers.as_deref(), "blockers", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(learnings.as_deref(), "learnings", MAX_LONG_TEXT_LENGTH)?;
    validate_optional_string_length(ai_synthesis.as_deref(), "ai_synthesis", MAX_AI_NOTES_LENGTH)?;

    let today = today_ymd_for_conn(conn)?;
    let date = lorvex_workflow::daily_review_date::resolve_daily_review_write_date(
        date.as_deref(),
        &today,
    )
    .map_err(|error| McpError::Validation(error.to_string()))?;

    let now = utc_now_iso();
    let before_row = lorvex_store::daily_review_ops::get_daily_review_row(conn, &date)?
        .map(serde_json::to_value)
        .transpose()?;
    let timezone = anchored_timezone_name(conn)?;
    let operation = if before_row.is_some() {
        "update"
    } else {
        "create"
    };

    // validate IDs reference existing rows before
    // writing the parent or materializing into the join tables —
    // phantom IDs would otherwise bump `daily_reviews` before failing.
    // The sibling `set_current_focus` path (#2888) gated `task_ids`
    // with the active-task existence check; the daily-review path was
    // unaudited until now.
    //
    // daily-review archived-task policy:
    //   • WRITE-time: reject archived task_ids via
    //     `validate_task_ids_active`. The assistant should not be able
    //     to pin a freshly-trashed task into a new (or amended) review
    //     — that is almost always a stale-context bug.
    //   • READ-time: tolerate post-write archival. `get_daily_review`
    //     returns `linked_task_ids` as a raw ID array (no enrichment
    //     against `archived_at`), so a task that was active when the
    //     review was written and archived later still surfaces as a
    //     pinned ID. Daily review is record-keeping; rewriting history
    //     when a target task is later trashed would erase the audit
    //     trail. The mismatch with the focus surface is intentional:
    //     focus is forward-looking (must be live), review is
    //     backward-looking (preserve what was true at write-time).
    if let Some(ref task_ids) = linked_task_ids {
        validate_task_ids_active(conn, task_ids, "linked_task_ids")?;
    }
    if let Some(ref list_ids) = linked_list_ids {
        validate_list_ids_exist(conn, list_ids, "linked_list_ids")?;
    }

    let mutation = AddDailyReviewMutation {
        date: date.as_str(),
        summary: summary.as_str(),
        mood: mood.map(i64::from),
        energy_level: energy_level.map(i64::from),
        linked_task_ids: linked_task_ids.as_deref(),
        linked_list_ids: linked_list_ids.as_deref(),
        wins: wins.as_deref(),
        blockers: blockers.as_deref(),
        learnings: learnings.as_deref(),
        ai_synthesis: ai_synthesis.as_deref(),
        timezone: timezone.as_str(),
        now: now.as_str(),
        operation,
        before: before_row,
    };
    let output = execute_mcp_mutation(conn, &mutation, "add_daily_review", date.as_str())?;

    Ok(serde_json::to_string(&output.after)?)
}
