use std::collections::HashMap;

use lorvex_domain::validation::{validate_date_format, validate_title};

use super::MAX_LIST_SLUG_LENGTH;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeepLinkTarget {
    Today,
    QuickCapture,
    Task {
        task_id: String,
    },
    Search {
        query: String,
    },
    AddTask {
        title: String,
        list: Option<String>,
        due: Option<String>,
        priority: Option<i64>,
    },
    CompleteTask {
        task_id: String,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
pub struct DeepLinkTargetPayload {
    pub route: String,
    pub task_id: Option<String>,
    /// Extra parameters for action-type deep links (add-task, search, etc.).
    #[serde(default, skip_serializing_if = "HashMap::is_empty")]
    pub params: HashMap<String, String>,
}

impl DeepLinkTarget {
    pub fn to_payload(&self) -> DeepLinkTargetPayload {
        match self {
            Self::Today => DeepLinkTargetPayload {
                route: "today".to_string(),
                task_id: None,
                params: HashMap::new(),
            },
            Self::QuickCapture => DeepLinkTargetPayload {
                route: "quick_capture".to_string(),
                task_id: None,
                params: HashMap::new(),
            },
            Self::Task { task_id } => DeepLinkTargetPayload {
                route: "task".to_string(),
                task_id: Some(task_id.clone()),
                params: HashMap::new(),
            },
            Self::Search { query } => {
                let mut params = HashMap::new();
                params.insert("q".to_string(), query.clone());
                DeepLinkTargetPayload {
                    route: "search".to_string(),
                    task_id: None,
                    params,
                }
            }
            Self::AddTask {
                title,
                list,
                due,
                priority,
            } => {
                let mut params = HashMap::new();
                params.insert("title".to_string(), title.clone());
                if let Some(list) = list {
                    params.insert("list".to_string(), list.clone());
                }
                if let Some(due) = due {
                    params.insert("due".to_string(), due.clone());
                }
                if let Some(priority) = priority {
                    params.insert("priority".to_string(), priority.to_string());
                }
                DeepLinkTargetPayload {
                    route: "add_task".to_string(),
                    task_id: None,
                    params,
                }
            }
            Self::CompleteTask { task_id } => DeepLinkTargetPayload {
                route: "complete_task".to_string(),
                task_id: Some(task_id.clone()),
                params: HashMap::new(),
            },
        }
    }

    pub(super) fn from_payload_result(
        payload: &DeepLinkTargetPayload,
    ) -> Result<Option<Self>, String> {
        match payload.route.as_str() {
            "today" => Ok(Some(Self::Today)),
            "quick_capture" => Ok(Some(Self::QuickCapture)),
            "task" => {
                let Some(task_id) = payload.task_id.as_ref() else {
                    return Err("task deep link payload requires non-empty task_id".to_string());
                };
                if task_id.is_empty() {
                    return Err("task deep link payload requires non-empty task_id".to_string());
                }
                // re-validate the task_id through the same
                // UUIDv7 gate used by the URL parser so the payload path
                // (used by acknowledge_pending_payload after sign-in or
                // window restore) can't deliver an arbitrary string to
                // downstream SQL / filesystem consumers.
                let task_id = super::parse::validate_task_id(task_id, "task")?;
                Ok(Some(Self::Task { task_id }))
            }
            "search" => {
                let Some(query) = payload.params.get("q").cloned() else {
                    return Err("search deep link payload requires non-empty 'q'".to_string());
                };
                if query.is_empty() {
                    Err("search deep link payload requires non-empty 'q'".to_string())
                } else {
                    Ok(Some(Self::Search { query }))
                }
            }
            "add_task" => {
                let Some(title) = payload.params.get("title").cloned() else {
                    return Err("add_task deep link payload requires non-empty 'title'".to_string());
                };
                if title.is_empty() {
                    return Err("add_task deep link payload requires non-empty 'title'".to_string());
                }
                // cap + format-validate the queued
                // payload just like the URL-parse path does.
                validate_title(&title)
                    .map_err(|e| format!("add_task deep link payload title: {e}"))?;

                let list = payload.params.get("list").cloned();
                if let Some(list_ref) = list.as_ref() {
                    if list_ref.chars().count() > MAX_LIST_SLUG_LENGTH {
                        return Err(format!(
                            "add_task deep link payload list is too long ({} chars; max {})",
                            list_ref.chars().count(),
                            MAX_LIST_SLUG_LENGTH
                        ));
                    }
                }
                let due = payload.params.get("due").cloned();
                if let Some(due_ref) = due.as_ref() {
                    validate_date_format(due_ref)
                        .map_err(|e| format!("add_task deep link payload due: {e}"))?;
                }
                // Match the URL-query path's 1..=3 bounds so the
                // two deep-link entry points agree. Storing
                // out-of-range values verbatim breaks downstream
                // queries that assume priority ∈ {1,2,3,NULL}
                // (today-view bucketing, `priority_effective` index).
                let priority = match payload.params.get("priority") {
                    Some(raw) => {
                        let parsed = raw.parse::<i64>().map_err(|_| {
                            "add_task deep link payload priority must be an integer".to_string()
                        })?;
                        if !(1..=3).contains(&parsed) {
                            return Err(
                                "add_task deep link payload priority must be between 1 and 3"
                                    .to_string(),
                            );
                        }
                        Some(parsed)
                    }
                    None => None,
                };
                Ok(Some(Self::AddTask {
                    title,
                    list,
                    due,
                    priority,
                }))
            }
            "complete_task" => {
                let Some(task_id) = payload.task_id.as_ref() else {
                    return Err(
                        "complete_task deep link payload requires non-empty task_id".to_string()
                    );
                };
                if task_id.is_empty() {
                    return Err(
                        "complete_task deep link payload requires non-empty task_id".to_string()
                    );
                }
                let task_id = super::parse::validate_task_id(task_id, "complete_task")?;
                Ok(Some(Self::CompleteTask { task_id }))
            }
            _ => Ok(None),
        }
    }
}
