//! Identity & content fields for a task. See [`crate::repositories::task::read::TaskRow`].

/// Identity & content fields for a task. See [`crate::repositories::task::read::TaskRow`].
///
/// #3289: fields are `pub(crate)` so the repo-internal row builder
/// (`task_from_row`) can populate them with struct literals during
/// SQL → Rust mapping, while external callers go through the borrow
/// accessors below for reads and [`TaskCore::new`] for writes. The
/// schema enforces `priority IN (1,2,3) OR priority IS NULL`; the
/// constructor mirrors that with a `debug_assert!` so a hand-built
/// `TaskCore` with `priority = Some(999)` surfaces in dev builds.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskCore {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) body: Option<String>,
    pub(crate) raw_input: Option<String>,
    pub(crate) ai_notes: Option<String>,
    pub(crate) status: String,
    pub(crate) list_id: String,
    pub(crate) priority: Option<i64>,
    pub(crate) version: String,
    pub(crate) created_at: String,
    pub(crate) updated_at: String,
}

/// Owned-field bundle accepted by [`TaskCore::new`]. Plain data carrier;
/// the validity invariants live on [`TaskCore`].
#[derive(Debug, Clone)]
pub struct TaskCoreFields {
    pub id: String,
    pub title: String,
    pub body: Option<String>,
    pub raw_input: Option<String>,
    pub ai_notes: Option<String>,
    pub status: String,
    pub list_id: String,
    pub priority: Option<i64>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
}

impl TaskCore {
    /// Build a [`TaskCore`] from owned fields. `priority` must be
    /// `None` or one of `Some(1)`, `Some(2)`, `Some(3)` — the schema
    /// CHECK is the canonical contract; we `debug_assert!` here so a
    /// hand-built fixture with an out-of-range priority surfaces in
    /// dev builds rather than silently sailing through the type system.
    pub fn new(fields: TaskCoreFields) -> Self {
        debug_assert!(
            matches!(fields.priority, None | Some(1..=3)),
            "TaskCore.priority must be None or 1..=3 (schema CHECK), got {:?}",
            fields.priority
        );
        Self {
            id: fields.id,
            title: fields.title,
            body: fields.body,
            raw_input: fields.raw_input,
            ai_notes: fields.ai_notes,
            status: fields.status,
            list_id: fields.list_id,
            priority: fields.priority,
            version: fields.version,
            created_at: fields.created_at,
            updated_at: fields.updated_at,
        }
    }

    pub fn id(&self) -> &str {
        &self.id
    }
    pub fn title(&self) -> &str {
        &self.title
    }
    pub fn body(&self) -> Option<&str> {
        self.body.as_deref()
    }
    pub fn raw_input(&self) -> Option<&str> {
        self.raw_input.as_deref()
    }
    pub fn ai_notes(&self) -> Option<&str> {
        self.ai_notes.as_deref()
    }
    pub fn status(&self) -> &str {
        &self.status
    }
    pub fn list_id(&self) -> &str {
        &self.list_id
    }
    pub const fn priority(&self) -> Option<i64> {
        self.priority
    }
    pub fn version(&self) -> &str {
        &self.version
    }
    pub fn created_at(&self) -> &str {
        &self.created_at
    }
    pub fn updated_at(&self) -> &str {
        &self.updated_at
    }

    /// Consume the wrapper and yield owned [`TaskCoreFields`]. Used by
    /// callers that map the row into a downstream model and need to move
    /// individual `String` fields without cloning.
    pub fn into_fields(self) -> TaskCoreFields {
        TaskCoreFields {
            id: self.id,
            title: self.title,
            body: self.body,
            raw_input: self.raw_input,
            ai_notes: self.ai_notes,
            status: self.status,
            list_id: self.list_id,
            priority: self.priority,
            version: self.version,
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}
