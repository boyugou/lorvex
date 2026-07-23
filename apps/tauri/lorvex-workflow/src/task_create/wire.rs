//! Wire shape for `task.batch_create` task entries.
//!
//! Translates the CLI's `--tasks-json` JSON payload into the workflow's
//! [`TaskCreateInput`]. Lives separately from the orchestrator so wire
//! validation does not bloat the create flow.

use lorvex_domain::Patch;

use super::input::TaskCreateInput;

/// Lift the wire shape's `Option<T>` into `Patch<T>` for the workflow
/// input. The CLI wire surface cannot express a distinct
/// `Patch::Clear` (missing key vs. JSON null are both deserialized as
/// `None` here), so both lower to `Patch::Unset`. The two states
/// collapse to the same NULL-on-insert in the writer regardless.
fn option_to_patch<T>(value: Option<T>) -> Patch<T> {
    match value {
        None => Patch::Unset,
        Some(v) => Patch::Set(v),
    }
}

/// Wire shape for `task.batch_create` task entries.
///
/// The CLI accepts `--tasks-json` as a JSON array whose entries match
/// `TaskCreateInput` field-for-field, with one shape divergence:
/// the entry's `recurrence` is a JSON object describing a
/// `RecurrenceRuleArgs`, not a pre-stringified blob. The wire shim
/// owns that translation (`recurrence` → `recurrence_json`) so callers
/// stop open-coding `take_required_string` / `take_optional_*` JSON
/// pickers per field.
///
/// `#[serde(deny_unknown_fields)]` mirrors the CLI's prior behavior of
/// surfacing typos as validation errors. `status` and `raw_input` are
/// intentionally NOT part of the wire shape — neither is reachable
/// from the existing CLI batch-create surface and admitting them
/// would silently change the verb's contract.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskCreateInputWire {
    pub title: String,
    #[serde(default)]
    pub list_id: Option<String>,
    #[serde(default)]
    pub priority: Option<u8>,
    #[serde(default)]
    pub due_date: Option<String>,
    #[serde(default)]
    pub due_time: Option<String>,
    #[serde(default)]
    pub planned_date: Option<String>,
    #[serde(default)]
    pub estimated_minutes: Option<u32>,
    #[serde(default)]
    pub tags: Option<Vec<String>>,
    #[serde(default)]
    pub body: Option<String>,
    #[serde(default)]
    pub ai_notes: Option<String>,
    #[serde(default)]
    pub depends_on: Option<Vec<String>>,
    #[serde(default)]
    pub reminders: Option<Vec<String>>,
    #[serde(default)]
    pub recurrence: Option<serde_json::Value>,
    #[serde(default)]
    pub completed: Option<bool>,
}

impl TaskCreateInputWire {
    /// Translate the wire shape into the workflow's [`TaskCreateInput`].
    /// Returns a validation message string on shape errors so the
    /// caller can map it to its own error type.
    pub fn into_workflow_input(self) -> Result<TaskCreateInput, String> {
        let recurrence_json = match self.recurrence {
            None | Some(serde_json::Value::Null) => None,
            Some(value) if value.is_object() => Some(value.to_string()),
            Some(_) => return Err("task recurrence must be a JSON object".to_string()),
        };
        Ok(TaskCreateInput {
            title: self.title,
            list_id: option_to_patch(self.list_id),
            priority: option_to_patch(self.priority),
            due_date: option_to_patch(self.due_date),
            due_time: option_to_patch(self.due_time),
            planned_date: option_to_patch(self.planned_date),
            estimated_minutes: option_to_patch(self.estimated_minutes),
            tags: self.tags,
            body: option_to_patch(self.body),
            raw_input: Patch::Unset,
            ai_notes: option_to_patch(self.ai_notes),
            depends_on: self.depends_on,
            reminders: self.reminders,
            recurrence_json: option_to_patch(recurrence_json),
            completed: self.completed,
            status: Patch::Unset,
        })
    }
}
