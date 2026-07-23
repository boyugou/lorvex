use schemars::JsonSchema;

use lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH;
use lorvex_domain::Patch;
use lorvex_mcp_derive::ContractValidate;

use super::IDEMPOTENCY_KEY_DESCRIPTION;

// ── Habit frequency type enum ───────────────────────────────────────

// derive `Serialize` so wrapping write-arg structs
// can compute the canonical request fingerprint for the idempotency
// cache checksum.
#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FrequencyType {
    Daily,
    Weekly,
    Monthly,
    TimesPerWeek,
}

pub(crate) const fn frequency_type_to_str(ft: FrequencyType) -> &'static str {
    match ft {
        FrequencyType::Daily => "daily",
        FrequencyType::Weekly => "weekly",
        FrequencyType::Monthly => "monthly",
        FrequencyType::TimesPerWeek => "times_per_week",
    }
}

// Every habit-write surface (8 tools) accepts the same optional
// short-circuit token so a retried `complete_habit` does not re-issue
// the atomic increment (which would double streak counts) and a
// retried `delete_habit` does not run the cascade twice (which would
// emit duplicate audit rows). The description string is hoisted into
// `server_contract` so all four contract modules share one wording.

// ── Habit CRUD ──────────────────────────────────────────────────────

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct CreateHabitArgs {
    #[schemars(description = "Name of the habit (e.g. 'Exercise', 'Read 30 minutes')")]
    pub(crate) name: String,
    #[schemars(description = "Emoji or icon identifier")]
    pub(crate) icon: Option<String>,
    #[schemars(description = "Hex color (e.g. '#4CAF50')")]
    pub(crate) color: Option<String>,
    #[schemars(description = "Optional cue or trigger that usually leads into this habit.")]
    pub(crate) cue: Option<String>,
    #[schemars(
        description = "Frequency type: daily (default), weekly, monthly, or times_per_week"
    )]
    pub(crate) frequency_type: Option<FrequencyType>,
    #[schemars(
        description = "For weekly cadence: the pinned weekday set as lowercase tokens (mon, tue, wed, thu, fri, sat, sun). Omit or empty for 'every day'. Ignored by other cadences."
    )]
    pub(crate) weekdays: Option<Vec<String>>,
    #[schemars(
        description = "For times_per_week cadence: completions required per week (the N in '3x/week'). Ignored by other cadences."
    )]
    pub(crate) per_period_target: Option<i64>,
    #[schemars(
        description = "For monthly cadence: the reminder day-of-month (1-31, clamped to the month's last day). Ignored by other cadences."
    )]
    pub(crate) day_of_month: Option<i64>,
    #[schemars(description = "Per-day accumulative goal (default 1), decoupled from cadence.")]
    pub(crate) target_count: Option<i64>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct UpdateHabitArgs {
    #[schemars(description = "Habit ID")]
    pub(crate) id: String,
    #[schemars(description = "New habit name")]
    pub(crate) name: Option<String>,
    #[schemars(description = "Emoji or icon identifier. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) icon: Patch<String>,
    #[schemars(description = "Hex color. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) color: Patch<String>,
    #[schemars(description = "Cue or trigger text. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) cue: Patch<String>,
    #[schemars(
        description = "Frequency type: daily, weekly, monthly, or times_per_week. Setting this replaces the entire cadence; the weekdays / per_period_target / day_of_month fields below supply the new cadence's detail."
    )]
    pub(crate) frequency_type: Option<FrequencyType>,
    #[schemars(
        description = "For weekly cadence: the pinned weekday set as lowercase tokens (mon..sun). Omit or empty for 'every day'. Only read when frequency_type is set."
    )]
    pub(crate) weekdays: Option<Vec<String>>,
    #[schemars(
        description = "For times_per_week cadence: completions required per week. Only read when frequency_type is set."
    )]
    pub(crate) per_period_target: Option<i64>,
    #[schemars(
        description = "For monthly cadence: the reminder day-of-month (1-31). Only read when frequency_type is set."
    )]
    pub(crate) day_of_month: Option<i64>,
    #[schemars(description = "Per-day accumulative goal, decoupled from cadence.")]
    pub(crate) target_count: Option<i64>,
    #[schemars(description = "Archive or unarchive the habit")]
    pub(crate) archived: Option<bool>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct DeleteHabitArgs {
    #[schemars(description = "ID of the habit to permanently delete")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(
        description = "Issue #2370: if true, run the delete (incl. cascade counts for completions + reminder policies), return the would-be shape with `dry_run: true`, and roll back. Default false."
    )]
    // schemars default mirrors serde's default so
    // strict assistant clients don't reject calls that omit the
    // field.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct CompleteHabitArgs {
    #[schemars(description = "Habit ID")]
    #[validate(uuid)]
    pub(crate) id: String,
    #[schemars(description = "Completion date (YYYY-MM-DD). Defaults to today.")]
    pub(crate) date: Option<String>,
    #[schemars(description = "Optional note for this completion")]
    #[validate(string, max_length = MAX_SHORT_TEXT_LENGTH)]
    pub(crate) note: Option<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct UncompleteHabitArgs {
    #[schemars(description = "Habit ID")]
    pub(crate) id: String,
    #[schemars(description = "Date to remove completion for (YYYY-MM-DD). Defaults to today.")]
    pub(crate) date: Option<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCompleteHabitArgs {
    #[schemars(description = "Habit IDs to complete. Each habit gets one completion increment.")]
    pub(crate) habit_ids: Vec<String>,
    #[schemars(
        description = "Completion date (YYYY-MM-DD). Defaults to today. Applies to all habits in the batch."
    )]
    pub(crate) date: Option<String>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetHabitCompletionsArgs {
    #[schemars(description = "Habit ID")]
    pub(crate) id: String,
    #[schemars(description = "Number of days to look back (default 30, max 365)")]
    pub(crate) days: Option<i64>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetHabitStatsArgs {
    #[schemars(description = "Habit ID")]
    pub(crate) id: String,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetHabitsSummaryArgs {
    #[schemars(description = "Include archived habits (default false)")]
    pub(crate) include_archived: Option<bool>,
}

// ── Habit Reminders ─────────────────────────────────────────────────

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetHabitReminderPoliciesArgs {}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct UpsertHabitReminderPolicyArgs {
    #[schemars(
        description = "Optional reminder slot ID. Omit to create a new reminder slot; provide id to update an existing slot for the same habit."
    )]
    pub(crate) id: Option<String>,
    #[schemars(description = "ID of the habit to set reminder for")]
    pub(crate) habit_id: String,
    #[schemars(description = "Daily reminder time in HH:MM (24h format, e.g. '07:00')")]
    pub(crate) reminder_time: String,
    #[schemars(description = "Whether the reminder is enabled. Default true.")]
    pub(crate) enabled: Option<bool>,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct DeleteHabitReminderPolicyArgs {
    #[schemars(description = "ID of the habit reminder policy to delete")]
    pub(crate) id: String,
    // dropping a reminder policy is destructive (the
    // policy row is hard-deleted, then a tombstone propagates to
    // peers). Let the assistant narrate the impending removal —
    // habit_name and reminder_time from the captured `before` —
    // before committing.
    #[schemars(
        description = "Issue #3019-H5: if true, run the delete (incl. tombstone synth + before snapshot capture) and return the would-be response with `dry_run: true`, then roll back. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
