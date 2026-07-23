//! Lifecycle timestamp fields for a task. See [`crate::repositories::task::read::TaskRow`].

/// Lifecycle timestamp fields for a task. See [`crate::repositories::task::read::TaskRow`].
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskLifecycleTimestamps {
    pub(crate) completed_at: Option<String>,
    /// soft-delete / Trash. `Some(ts)` means the task is in
    /// the Trash and must be hidden from every user-facing read path
    /// (lists, stats, search, counts). The Trash view is the only place
    /// that sets `include_archived = true` and surfaces these rows.
    /// `None` means the task is active.
    pub(crate) archived_at: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct TaskLifecycleTimestampsFields {
    pub completed_at: Option<String>,
    pub archived_at: Option<String>,
}

impl TaskLifecycleTimestamps {
    pub fn new(fields: TaskLifecycleTimestampsFields) -> Self {
        Self {
            completed_at: fields.completed_at,
            archived_at: fields.archived_at,
        }
    }

    pub fn completed_at(&self) -> Option<&str> {
        self.completed_at.as_deref()
    }
    pub fn archived_at(&self) -> Option<&str> {
        self.archived_at.as_deref()
    }

    pub fn into_fields(self) -> TaskLifecycleTimestampsFields {
        TaskLifecycleTimestampsFields {
            completed_at: self.completed_at,
            archived_at: self.archived_at,
        }
    }
}
