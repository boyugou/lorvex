use super::super::{
    IDEMPOTENCY_KEY_DESCRIPTION, SET_RECURRENCE_BYDAY_FIELD_DESCRIPTION,
    SET_RECURRENCE_UNTIL_FIELD_DESCRIPTION,
};
use crate::contract::MAX_AI_NOTES_LENGTH;
use lorvex_domain::validation::{MAX_BODY_LENGTH, MAX_SHORT_TEXT_LENGTH};
use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;
use serde_json::{json, Map, Value};

#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum RecurrenceFreq {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

impl RecurrenceFreq {
    pub(crate) const fn as_canonical_str(self) -> &'static str {
        match self {
            RecurrenceFreq::Daily => "DAILY",
            RecurrenceFreq::Weekly => "WEEKLY",
            RecurrenceFreq::Monthly => "MONTHLY",
            RecurrenceFreq::Yearly => "YEARLY",
        }
    }
}

/// canonical structured shape for task recurrence rule
/// inputs.
/// `RecurrenceFreq` + named scalar fields but every other write path
/// (`create_task`, `update_task`, `batch_create_tasks`,
/// `batch_update_tasks`) accepted `recurrence: Option<String>`
/// carrying a hand-parsed RRULE-aligned JSON blob. The same domain
/// concept therefore had two contracts: one validated by serde at
/// the parse boundary, and one validated by hand at execute time —
/// silently drifting whenever new RFC 5545 modifiers (BYMONTH,
/// BYSETPOS, …) were added to the canonical normalizer.
///
/// `RecurrenceRuleArgs` is now the single typed shape every write
/// surface accepts. Its fields mirror the RFC 5545 §3.3.10 modifiers
/// the canonical [`lorvex_domain::validation::normalize_task_recurrence`]
/// already understands. The struct serializes to the same JSON shape
/// the normalizer expects, so consumers convert via
/// [`RecurrenceRuleArgs::to_rule_json`] (or its `&str`-returning sibling
/// [`RecurrenceRuleArgs::to_rule_json_string`]) and pipe the result
/// through the existing normalizer — keeping range/cardinality/UNTIL
/// parsing (date-only vs RFC 5545 DATE-TIME) in one canonical place.
///
/// The schema does NOT carry `recurrence_exceptions`. Those are
/// stored in a separate `task_recurrence_exceptions` table and
/// mutated via `add_task_recurrence_exception` /
/// `remove_task_recurrence_exception` — they are not part of the
/// recurrence *rule* and therefore have no place on this struct.
#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct RecurrenceRuleArgs {
    #[schemars(
        description = "Recurrence frequency: daily, weekly, monthly, yearly (RRULE-aligned: stored as DAILY/WEEKLY/MONTHLY/YEARLY)."
    )]
    pub(crate) freq: RecurrenceFreq,
    #[schemars(
        description = "Repeat interval (e.g. 2 = every 2 weeks when freq=weekly). Default 1. Stored as INTERVAL."
    )]
    pub(crate) interval: Option<u32>,
    #[schemars(description = SET_RECURRENCE_BYDAY_FIELD_DESCRIPTION)]
    pub(crate) byday: Option<Vec<String>>,
    #[schemars(
        description = "BYMONTH filter (1..=12). Only valid for WEEKLY/MONTHLY/YEARLY recurrence. Most commonly paired with BYMONTHDAY for YEARLY birthdays."
    )]
    pub(crate) bymonth: Option<Vec<i64>>,
    #[schemars(
        description = "Days of month for monthly/yearly recurrence, an array of ints in -31..=-1 / 1..=31 (e.g. [1,15] = 1st and 15th; negative counts from month end, -1 = last day). Sorted + deduped. Stored as BYMONTHDAY."
    )]
    pub(crate) bymonthday: Option<Vec<i64>>,
    #[schemars(
        description = "BYSETPOS — for monthly/yearly rules, pick the Nth occurrence inside a frequency-defined set (-366..=-1, 1..=366). Combine with BYDAY (e.g. 'first weekday of month')."
    )]
    pub(crate) bysetpos: Option<Vec<i64>>,
    #[schemars(
        description = "WKST — week-start weekday (MO|TU|WE|TH|FR|SA|SU). Used by WEEKLY rules with INTERVAL > 1 to determine week boundaries."
    )]
    pub(crate) wkst: Option<String>,
    #[schemars(description = SET_RECURRENCE_UNTIL_FIELD_DESCRIPTION)]
    pub(crate) until: Option<String>,
    #[schemars(
        description = "Maximum number of occurrences before the recurrence ends. Mutually exclusive with until. Stored as COUNT."
    )]
    pub(crate) count: Option<u32>,
}

impl RecurrenceRuleArgs {
    /// Build the unnormalized JSON shape the canonical
    /// [`lorvex_domain::validation::normalize_task_recurrence`]
    /// expects. The normalizer enforces range checks,
    /// cardinality (COUNT vs UNTIL exclusivity), and stable key
    /// ordering — keeping that one source of truth instead of
    /// duplicating the rules at every write surface.
    pub(crate) fn to_rule_json(&self) -> Value {
        let mut rule = Map::new();
        rule.insert(
            "FREQ".to_string(),
            Value::String(self.freq.as_canonical_str().to_string()),
        );
        if let Some(interval) = self.interval {
            rule.insert("INTERVAL".to_string(), json!(interval));
        }
        if let Some(ref byday_values) = self.byday {
            if !byday_values.is_empty() {
                rule.insert(
                    "BYDAY".to_string(),
                    Value::Array(byday_values.iter().cloned().map(Value::String).collect()),
                );
            }
        }
        if let Some(ref months) = self.bymonth {
            if !months.is_empty() {
                rule.insert("BYMONTH".to_string(), json!(months));
            }
        }
        if let Some(ref days) = self.bymonthday {
            if !days.is_empty() {
                rule.insert("BYMONTHDAY".to_string(), json!(days));
            }
        }
        if let Some(ref positions) = self.bysetpos {
            if !positions.is_empty() {
                rule.insert("BYSETPOS".to_string(), json!(positions));
            }
        }
        if let Some(ref wkst) = self.wkst {
            rule.insert("WKST".to_string(), Value::String(wkst.clone()));
        }
        if let Some(ref until) = self.until {
            rule.insert("UNTIL".to_string(), Value::String(until.clone()));
        }
        if let Some(count) = self.count {
            rule.insert("COUNT".to_string(), json!(count));
        }
        Value::Object(rule)
    }

    /// Serialize the rule to the JSON string shape the canonical
    /// normalizer consumes. Convenience over `to_rule_json` for
    /// callers that immediately need a `&str`.
    pub(crate) fn to_rule_json_string(&self) -> String {
        self.to_rule_json().to_string()
    }
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct SetRecurrenceArgs {
    #[schemars(description = "Task ID")]
    pub(crate) id: String,
    #[serde(flatten)]
    pub(crate) rule: RecurrenceRuleArgs,
    // #3029-H2: optional idempotency token. A retried
    // `set_recurrence` after a transport flake would otherwise
    // re-stamp the same rule as a fresh write — peers see two
    // version-bumped envelopes and the changelog records two
    // identical "Set recurrence" rows. Mirror the H4 cache pattern.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate recurrence writes; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct SetTaskAiNotesArgs {
    #[schemars(description = "Task ID whose assistant context should be replaced")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(description = "Current assistant context for this task; empty clears it")]
    #[validate(string, max_length = MAX_AI_NOTES_LENGTH)]
    pub(crate) notes: String,
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate assistant-context writes; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct AppendToTaskBodyArgs {
    #[schemars(description = "Task ID")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "Text to append to the task body/notes. Added after a blank line separator if the body already has content."
    )]
    #[validate(string, max_length = MAX_BODY_LENGTH)]
    pub(crate) text: String,
    // #3029-H2: optional idempotency token. A retry without this
    // key duplicates the appended body block (separator and all),
    // visible to the user.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate body appends; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct CompleteTaskArgs {
    #[schemars(description = "Task ID to mark as completed")]
    #[validate(uuid)]
    pub(crate) id: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`. Without it, a transport flake during
    // the response leg of a successful retry caused the assistant to
    // retry the call and silently double-process the completion
    // (recurrence successor spawned twice, completion sound twice).
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate completions; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct ReopenTaskArgs {
    #[schemars(description = "Task ID to reopen (set back to open status)")]
    #[validate(uuid)]
    pub(crate) id: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate reopens; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct CancelTaskArgs {
    #[schemars(description = "Task ID to cancel")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(description = "Optional cancellation reason")]
    #[validate(string, max_length = MAX_SHORT_TEXT_LENGTH)]
    pub(crate) reason: Option<String>,
    #[schemars(
        description = "If true and the task is recurring, stop the entire series (clear recurrence rule, do not spawn next occurrence). Default false: skip this occurrence and spawn the next one."
    )]
    pub(crate) cancel_series: Option<bool>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate cancellations; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    // cancel cascades through reminders, dependency
    // edges, focus schedules, and (for recurring tasks) spawns a
    // successor — destructive enough that the assistant should be able
    // to preview the cascade before committing.
    #[schemars(
        description = "Issue #3019-H5: if true, run the cancel transition (incl. cascade through reminders, dependencies, focus, recurrence successor spawn) and return the would-be shape with `dry_run: true`, then roll back. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct DeferTaskArgs {
    #[schemars(description = "Task ID to defer")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "Absolute planned date target in YYYY-MM-DD. Canonical deferral semantics are absolute, not relative."
    )]
    pub(crate) until_date: String,
    #[schemars(description = "Why the task is being deferred (appended to ai_notes)")]
    #[validate(string, max_length = MAX_SHORT_TEXT_LENGTH)]
    pub(crate) reason: Option<String>,
    #[schemars(
        description = "Structured defer reason: not_today, blocked, low_energy, needs_breakdown, needs_info. Stored in last_defer_reason column."
    )]
    pub(crate) structured_reason: Option<String>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`. Without it, a transport flake during a
    // successful retry caused the assistant to retry defer_task and
    // double-bump the defer_count plus duplicate the ai_notes line.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate defers; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct SetTaskRemindersArgs {
    #[schemars(description = "Task ID")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "Array of ISO reminder timestamps. Replaces all pending (non-notified) reminders."
    )]
    pub(crate) reminders: Vec<String>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate reminder rewrites; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct AddTaskReminderArgs {
    #[schemars(description = "Task ID")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "RFC 3339 datetime for the reminder (e.g. '2025-12-01T09:00:00Z'). Must be a valid ISO 8601 timestamp with timezone."
    )]
    pub(crate) reminder_at: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`. Without it, a transport flake during a
    // successful retry double-added the same reminder for the same
    // task — the user got two notifications.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate reminder additions; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct AddTaskChecklistItemArgs {
    #[schemars(description = "Task ID")]
    pub(crate) id: String,
    #[schemars(description = "Checklist item text")]
    pub(crate) text: String,
    #[schemars(description = "Optional zero-based insert position. Omit to append at the end.")]
    pub(crate) position: Option<u32>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`. Without it, a transport flake on a
    // successful retry caused the assistant to add the same checklist
    // item twice — the user saw a duplicate row.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate checklist additions; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct UpdateTaskChecklistItemArgs {
    #[schemars(description = "Checklist item ID")]
    pub(crate) item_id: String,
    #[schemars(description = "Updated checklist item text")]
    pub(crate) text: String,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct ToggleTaskChecklistItemArgs {
    #[schemars(description = "Checklist item ID")]
    pub(crate) item_id: String,
    #[schemars(
        description = "Explicit completion target. Use true to mark complete, false to mark incomplete."
    )]
    pub(crate) completed: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct RemoveTaskChecklistItemArgs {
    #[schemars(description = "Checklist item ID to remove")]
    pub(crate) item_id: String,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct ReorderTaskChecklistItemsArgs {
    #[schemars(description = "Task ID")]
    pub(crate) id: String,
    #[schemars(
        description = "Ordered checklist item IDs for the task. Must contain every existing checklist item exactly once."
    )]
    pub(crate) item_ids: Vec<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

// `Serialize` required so the idempotency-cache
// fingerprint (`canonical_request_repr`) can checksum the call.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct RemoveTaskReminderArgs {
    #[schemars(description = "Task ID")]
    #[validate(uuid)]
    pub(crate) task_id: String,
    #[schemars(description = "Reminder ID to remove")]
    #[validate(uuid)]
    pub(crate) reminder_id: String,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct PermanentDeleteTaskArgs {
    #[schemars(description = "Task ID to permanently delete")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "Issue #2370: if true, run the permanent-delete checks (archive gate, dependency cleanup) and return the would-be shape with `dry_run: true`, then roll back. Default false."
    )]
    // schemars must mirror serde's default so the
    // emitted JSON Schema marks `dry_run` optional.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct AddTaskRecurrenceExceptionArgs {
    #[schemars(description = "Task ID")]
    pub(crate) task_id: String,
    #[schemars(
        description = "Exception date to add (YYYY-MM-DD). Must be a valid occurrence of the task's recurrence pattern."
    )]
    pub(crate) exception_date: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate exception additions; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

// `Serialize` required for the idempotency-cache fingerprint.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct RemoveTaskRecurrenceExceptionArgs {
    #[schemars(description = "Task ID")]
    pub(crate) task_id: String,
    #[schemars(description = "Exception date to remove (YYYY-MM-DD)")]
    pub(crate) exception_date: String,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
