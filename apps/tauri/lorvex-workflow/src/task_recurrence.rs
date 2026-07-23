use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Map, Value};

use crate::recurrence_config::{DueAtPatch, RecurrenceChangeError};
use crate::task_response::{load_enriched_task_json, task_title};

#[derive(Debug, Clone)]
pub struct TaskRecurrenceRuleInput {
    pub freq: String,
    pub interval: Option<u32>,
    pub byday: Option<Vec<String>>,
    pub bymonth: Option<Vec<i64>>,
    pub bymonthday: Option<Vec<i64>>,
    pub bysetpos: Option<Vec<i64>>,
    pub wkst: Option<String>,
    pub until: Option<String>,
    pub count: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct SetTaskRecurrenceInput {
    pub task_id: TaskId,
    pub rule: TaskRecurrenceRuleInput,
}

#[derive(Debug, Clone)]
pub struct TaskRecurrenceMutationResult {
    pub task_id: String,
    pub before_task: Value,
    pub after_task: Value,
    pub summary: String,
}

fn recurrence_change_error_to_store(error: RecurrenceChangeError) -> StoreError {
    match error {
        RecurrenceChangeError::ClearDueDateOnRecurring => {
            StoreError::Validation("recurring tasks must have a due_date".to_string())
        }
        RecurrenceChangeError::DueTimeWithoutDueDate => StoreError::Validation(
            "due_time without due_date is invalid: a clock time requires a calendar day"
                .to_string(),
        ),
        RecurrenceChangeError::Db(error) => StoreError::from(error),
        RecurrenceChangeError::TransactionWrap(message) => {
            StoreError::Invariant(format!("transaction wrapper failure: {message}"))
        }
        RecurrenceChangeError::StaleVersion { task_id } => StoreError::StaleVersion {
            entity: ENTITY_TASK,
            id: task_id,
        },
    }
}

fn canonical_freq(raw: &str) -> Result<&'static str, StoreError> {
    match raw.trim().to_ascii_uppercase().as_str() {
        "DAILY" => Ok("DAILY"),
        "WEEKLY" => Ok("WEEKLY"),
        "MONTHLY" => Ok("MONTHLY"),
        "YEARLY" => Ok("YEARLY"),
        _ => Err(StoreError::Validation(
            "freq must be one of daily, weekly, monthly, yearly".to_string(),
        )),
    }
}

fn to_rule_json_string(rule: &TaskRecurrenceRuleInput) -> Result<String, StoreError> {
    if rule.byday.as_ref().is_some_and(Vec::is_empty) {
        return Err(StoreError::Validation(
            "BYDAY array must contain at least one weekday code (or be omitted)".to_string(),
        ));
    }

    let mut object = Map::new();
    object.insert(
        "FREQ".to_string(),
        Value::String(canonical_freq(&rule.freq)?.to_string()),
    );
    if let Some(interval) = rule.interval {
        object.insert("INTERVAL".to_string(), json!(interval));
    }
    if let Some(byday) = rule.byday.as_ref().filter(|values| !values.is_empty()) {
        object.insert(
            "BYDAY".to_string(),
            Value::Array(byday.iter().cloned().map(Value::String).collect()),
        );
    }
    if let Some(bymonth) = rule.bymonth.as_ref().filter(|values| !values.is_empty()) {
        object.insert("BYMONTH".to_string(), json!(bymonth));
    }
    if let Some(bymonthday) = rule.bymonthday.as_ref().filter(|values| !values.is_empty()) {
        object.insert("BYMONTHDAY".to_string(), json!(bymonthday));
    }
    if let Some(bysetpos) = rule.bysetpos.as_ref().filter(|values| !values.is_empty()) {
        object.insert("BYSETPOS".to_string(), json!(bysetpos));
    }
    if let Some(wkst) = &rule.wkst {
        object.insert("WKST".to_string(), Value::String(wkst.clone()));
    }
    if let Some(until) = &rule.until {
        object.insert("UNTIL".to_string(), Value::String(until.clone()));
    }
    if let Some(count) = rule.count {
        object.insert("COUNT".to_string(), json!(count));
    }
    Ok(Value::Object(object).to_string())
}

fn recurrence_summary(title: &str, rule: &TaskRecurrenceRuleInput, freq_label: &str) -> String {
    let interval_part = if rule.interval.unwrap_or(1) > 1 {
        format!(" every {}", rule.interval.unwrap_or(1))
    } else {
        String::new()
    };
    let byday_part = rule
        .byday
        .as_ref()
        .filter(|values| !values.is_empty())
        .map(|values| format!(" on {}", values.join(",")))
        .unwrap_or_default();
    let bymonthday_part = rule
        .bymonthday
        .as_ref()
        .filter(|values| !values.is_empty())
        .map(|days| {
            let joined = days
                .iter()
                .map(i64::to_string)
                .collect::<Vec<_>>()
                .join(",");
            format!(" on day {joined}")
        })
        .unwrap_or_default();
    let count_part = rule
        .count
        .map(|count| format!(" for {count} occurrences"))
        .unwrap_or_default();
    let until_part = rule
        .until
        .as_ref()
        .map(|until| format!(" until {until}"))
        .unwrap_or_default();
    format!(
        "Set recurrence on '{title}': {freq_label}{interval_part}{byday_part}{bymonthday_part}{count_part}{until_part}"
    )
}

pub fn set_task_recurrence(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: SetTaskRecurrenceInput,
) -> Result<TaskRecurrenceMutationResult, StoreError> {
    let SetTaskRecurrenceInput { task_id, rule } = input;
    let freq_label = canonical_freq(&rule.freq)?;
    let raw_json = to_rule_json_string(&rule)?;
    let recurrence_json = lorvex_domain::validation::normalize_task_recurrence(&raw_json)?
        .ok_or_else(|| {
            StoreError::Validation(
                "recurrence rule resulted in empty after normalization".to_string(),
            )
        })?;

    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let now = lorvex_domain::sync_timestamp_now();
    let today = crate::timezone::today_ymd_for_conn(conn)?;
    let version = hlc.next_version_string();
    crate::recurrence_config::apply_recurrence_change(
        conn,
        &task_id,
        lorvex_domain::Patch::Set(recurrence_json),
        DueAtPatch::not_present(),
        &today,
        &version,
        &now,
    )
    .map_err(recurrence_change_error_to_store)?;

    let after = load_enriched_task_json(conn, &task_id)?;
    let summary = recurrence_summary(&title, &rule, freq_label);
    Ok(TaskRecurrenceMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary,
    })
}
