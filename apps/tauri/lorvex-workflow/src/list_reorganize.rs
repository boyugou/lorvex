use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};

use lorvex_domain::naming::STATUS_OPEN;
use lorvex_store::StoreError;
use rusqlite::params_from_iter;
use rusqlite::types::{Value as SqlValue, ValueRef};
use rusqlite::{Connection, Row};
use serde_json::{json, Map, Number, Value};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReorganizeListStrategy {
    Deadline,
    Priority,
    Manual,
}

impl ReorganizeListStrategy {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Deadline => "deadline",
            Self::Priority => "priority",
            Self::Manual => "manual",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ReorganizeListInput {
    pub list_id: String,
    pub strategy: ReorganizeListStrategy,
    pub task_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone)]
pub struct ReorganizeListResult {
    pub list_id: String,
    pub payload: Value,
    pub summary: String,
    pub before_json: Value,
    pub after_json: Value,
}

fn query_all_as_json(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Vec<Value>, StoreError> {
    let mut stmt = conn.prepare_cached(sql)?;
    let columns: Vec<String> = stmt
        .column_names()
        .iter()
        .map(ToString::to_string)
        .collect();
    let rows = stmt.query_map(params, |row| row_to_json(row, &columns))?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn query_one_as_json(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Option<Value>, StoreError> {
    let mut stmt = conn.prepare_cached(sql)?;
    let columns: Vec<String> = stmt
        .column_names()
        .iter()
        .map(ToString::to_string)
        .collect();
    let mut rows = stmt.query(params)?;
    if let Some(row) = rows.next()? {
        return Ok(Some(row_to_json(row, &columns)?));
    }
    Ok(None)
}

fn row_to_json(row: &Row<'_>, columns: &[String]) -> Result<Value, rusqlite::Error> {
    let mut object = Map::with_capacity(columns.len());
    for (index, key) in columns.iter().enumerate() {
        let value = match row.get_ref(index)? {
            ValueRef::Null => Value::Null,
            ValueRef::Integer(v) => Value::Number(Number::from(v)),
            ValueRef::Real(v) => Number::from_f64(v).map_or(Value::Null, Value::Number),
            ValueRef::Text(v) => Value::String(
                std::str::from_utf8(v)
                    .map_err(|error| {
                        rusqlite::Error::FromSqlConversionFailure(
                            index,
                            rusqlite::types::Type::Text,
                            Box::new(error),
                        )
                    })?
                    .to_string(),
            ),
            ValueRef::Blob(v) => Value::String(bytes_to_hex(v)),
        };
        object.insert(key.clone(), value);
    }
    Ok(Value::Object(object))
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(&mut out, "{byte:02x}");
    }
    out
}

fn sort_open_tasks_by_strategy(open_tasks: &mut [Value], strategy: ReorganizeListStrategy) {
    match strategy {
        ReorganizeListStrategy::Deadline => {
            open_tasks.sort_by(|a, b| {
                let a_due = a.get("due_date").and_then(Value::as_str);
                let b_due = b.get("due_date").and_then(Value::as_str);
                match (a_due, b_due) {
                    (None, None) => Ordering::Equal,
                    (None, Some(_)) => Ordering::Greater,
                    (Some(_), None) => Ordering::Less,
                    (Some(a_due), Some(b_due)) => a_due.cmp(b_due),
                }
            });
        }
        ReorganizeListStrategy::Priority => {
            open_tasks.sort_by(|a, b| {
                let a_priority = a.get("priority").and_then(Value::as_i64).unwrap_or(99);
                let b_priority = b.get("priority").and_then(Value::as_i64).unwrap_or(99);
                match a_priority.cmp(&b_priority) {
                    Ordering::Equal => {
                        let a_due = a.get("due_date").and_then(Value::as_str);
                        let b_due = b.get("due_date").and_then(Value::as_str);
                        match (a_due, b_due) {
                            (None, None) => Ordering::Equal,
                            (None, Some(_)) => Ordering::Greater,
                            (Some(_), None) => Ordering::Less,
                            (Some(a_d), Some(b_d)) => a_d.cmp(b_d),
                        }
                    }
                    other => other,
                }
            });
        }
        ReorganizeListStrategy::Manual => {}
    }
}

fn ordered_task_ids_for_strategy(
    conn: &Connection,
    list_id: &str,
    strategy: ReorganizeListStrategy,
    task_ids: Option<Vec<String>>,
) -> Result<Vec<String>, StoreError> {
    match strategy {
        ReorganizeListStrategy::Manual => {
            let ids = task_ids.ok_or_else(|| {
                StoreError::Validation("task_ids required for manual strategy".to_string())
            })?;
            let expected_open_ids: Vec<String> = conn
                .prepare_cached(
                    "SELECT id FROM tasks \
                     WHERE list_id = ?1 AND status = ?2 AND archived_at IS NULL \
                     ORDER BY id",
                )?
                .query_map([list_id, STATUS_OPEN], |row| row.get(0))?
                .collect::<Result<Vec<_>, _>>()?;

            if ids.is_empty() && !expected_open_ids.is_empty() {
                return Err(StoreError::Validation(
                    "task_ids required for manual strategy".to_string(),
                ));
            }
            let mut duplicate_ids: Vec<String> = Vec::new();
            let mut seen_ids = HashSet::new();
            for id in &ids {
                if !seen_ids.insert(id.clone()) && !duplicate_ids.contains(id) {
                    duplicate_ids.push(id.clone());
                }
            }
            if !duplicate_ids.is_empty() {
                return Err(StoreError::Validation(format!(
                    "task_ids contains duplicate ids: {}",
                    duplicate_ids.join(", ")
                )));
            }

            let placeholders: Vec<&str> = ids.iter().map(|_| "?").collect();
            let sql = format!(
                "SELECT id, list_id, status FROM tasks \
                 WHERE id IN ({}) AND archived_at IS NULL",
                placeholders.join(", ")
            );
            let params: Vec<SqlValue> = ids.iter().map(|id| SqlValue::Text(id.clone())).collect();
            let mut stmt = conn.prepare(&sql)?;
            let rows: Vec<(String, String, String)> = stmt
                .query_map(params_from_iter(params.iter()), |row| {
                    Ok((row.get(0)?, row.get(1)?, row.get(2)?))
                })?
                .collect::<Result<Vec<_>, _>>()?;

            let mut found_by_id: HashMap<String, (String, String)> = HashMap::new();
            for (id, row_list_id, status) in rows {
                found_by_id.insert(id, (row_list_id, status));
            }

            let mut seen_missing = HashSet::new();
            let mut missing: Vec<String> = Vec::new();
            for id in &ids {
                if !found_by_id.contains_key(id) && seen_missing.insert(id.clone()) {
                    missing.push(id.clone());
                }
            }
            if !missing.is_empty() {
                return Err(StoreError::Validation(format!(
                    "task(s) {} not found",
                    missing.join(", ")
                )));
            }

            let mut invalid_list: Vec<String> = Vec::new();
            let mut invalid_status: Vec<String> = Vec::new();
            let mut seen_invalid_list = HashSet::new();
            let mut seen_invalid_status = HashSet::new();
            for id in &ids {
                let (row_list_id, status) = found_by_id
                    .get(id)
                    .expect("missing ids already rejected above");
                if row_list_id != list_id && seen_invalid_list.insert(id.clone()) {
                    invalid_list.push(id.clone());
                }
                if status != STATUS_OPEN && seen_invalid_status.insert(id.clone()) {
                    invalid_status.push(id.clone());
                }
            }

            if !invalid_list.is_empty() {
                return Err(StoreError::Validation(format!(
                    "task(s) {} do not belong to list {list_id}",
                    invalid_list.join(", ")
                )));
            }
            if !invalid_status.is_empty() {
                return Err(StoreError::Validation(format!(
                    "task(s) {} are not open and cannot be manually reordered",
                    invalid_status.join(", ")
                )));
            }

            let provided_id_set: HashSet<&str> = ids.iter().map(String::as_str).collect();
            let missing_open_ids: Vec<String> = expected_open_ids
                .into_iter()
                .filter(|id| !provided_id_set.contains(id.as_str()))
                .collect();
            if !missing_open_ids.is_empty() {
                return Err(StoreError::Validation(format!(
                    "task_ids must include every open task in list {list_id}; missing: {}",
                    missing_open_ids.join(", ")
                )));
            }
            Ok(ids)
        }
        ReorganizeListStrategy::Deadline | ReorganizeListStrategy::Priority => {
            let mut open_tasks = query_all_as_json(
                conn,
                &format!(
                    "SELECT id, due_date, priority \
                     FROM tasks \
                     WHERE list_id = ? AND status = '{STATUS_OPEN}' AND archived_at IS NULL"
                ),
                [list_id.to_string()],
            )?;
            sort_open_tasks_by_strategy(&mut open_tasks, strategy);
            Ok(open_tasks
                .into_iter()
                .filter_map(|task| task.get("id").and_then(Value::as_str).map(str::to_string))
                .collect())
        }
    }
}

pub fn reorganize_list(
    conn: &Connection,
    input: ReorganizeListInput,
) -> Result<ReorganizeListResult, StoreError> {
    let ReorganizeListInput {
        list_id,
        strategy,
        task_ids,
    } = input;
    let list = query_one_as_json(conn, "SELECT * FROM lists WHERE id = ?", [list_id.clone()])?
        .ok_or_else(|| StoreError::NotFound {
            entity: "list",
            id: list_id.clone(),
        })?;
    let list_name = list
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_string();
    let ordered_ids = ordered_task_ids_for_strategy(conn, &list_id, strategy, task_ids)?;
    let tasks = if ordered_ids.is_empty() {
        Vec::new()
    } else {
        let placeholders = ordered_ids
            .iter()
            .map(|_| "?")
            .collect::<Vec<_>>()
            .join(", ");
        let sql =
            format!("SELECT * FROM tasks WHERE id IN ({placeholders}) AND archived_at IS NULL");
        let params: Vec<SqlValue> = ordered_ids
            .iter()
            .map(|id| SqlValue::Text(id.clone()))
            .collect();
        let unordered = query_all_as_json(conn, &sql, params_from_iter(params.iter()))?;
        let id_order: HashMap<&str, usize> = ordered_ids
            .iter()
            .enumerate()
            .map(|(i, id)| (id.as_str(), i))
            .collect();
        let mut sorted = unordered;
        sorted.sort_by_key(|task| {
            task.get("id")
                .and_then(Value::as_str)
                .and_then(|id| id_order.get(id).copied())
                .unwrap_or(usize::MAX)
        });
        sorted
    };

    let computed_order: Vec<&str> = tasks
        .iter()
        .filter_map(|task| task.get("id").and_then(Value::as_str))
        .collect();
    let strategy_name = strategy.as_str();
    let before_json = json!({
        "list_id": list_id,
        "strategy": strategy_name,
    });
    let after_json = json!({
        "list_id": list_id,
        "ordered_task_ids": computed_order,
    });
    let summary = format!(
        "Reorganized {} task(s) in list \"{list_name}\" by {strategy_name}",
        tasks.len()
    );

    let mut payload = list;
    if let Some(obj) = payload.as_object_mut() {
        obj.insert("tasks".to_string(), Value::Array(tasks));
    } else {
        payload = json!({ "tasks": tasks });
    }

    Ok(ReorganizeListResult {
        list_id,
        payload,
        summary,
        before_json,
        after_json,
    })
}
