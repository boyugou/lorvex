//! `TaskUpdateFields` — the borrow-only patch shape the CLI surface
//! consumes from its argument parser and translates into the canonical
//! [`lorvex_workflow::task_update::TaskUpdateInput`] at the boundary in
//! [`super::update`].
//!
//! Validation lives in the canonical workflow layer; this module only
//! owns the per-field changed-field reporting + the convenience
//! `has_any_patch` / `changes_tags` / `changes_dependencies` checks the
//! adapter uses before opening its outer transaction.

#[derive(Debug, Clone, Default)]
pub(crate) struct TaskUpdateFields<'a> {
    pub(crate) title: Option<&'a str>,
    pub(crate) body: lorvex_domain::Patch<&'a str>,
    pub(crate) ai_notes: lorvex_domain::Patch<&'a str>,
    // parity with MCP `update_task`. `status` patches
    // the lifecycle column (`open`/`completed`/`cancelled`/`someday`);
    // `raw_input` mirrors the AI-side "preserve unprocessed phrasing"
    // semantics. Both are flat options because neither column
    // supports a "clear to NULL" affordance through this surface
    // today — `status` is NOT NULL in the schema and `raw_input` is
    // not exposed as clearable on the CLI surface. Add the clear
    // branch when either column grows a real "unset" semantic.
    pub(crate) status: Option<&'a str>,
    pub(crate) raw_input: Option<&'a str>,
    pub(crate) list_id: Option<&'a str>,
    pub(crate) priority: lorvex_domain::Patch<i64>,
    pub(crate) due_date: lorvex_domain::Patch<&'a str>,
    pub(crate) due_time: lorvex_domain::Patch<&'a str>,
    pub(crate) planned_date: lorvex_domain::Patch<&'a str>,
    pub(crate) estimated_minutes: lorvex_domain::Patch<i64>,
    pub(crate) tags_set: Option<&'a [String]>,
    pub(crate) tags_add: Option<&'a [String]>,
    pub(crate) tags_remove: Option<&'a [String]>,
    pub(crate) depends_on_set: Option<&'a [String]>,
    pub(crate) depends_on_add: Option<&'a [String]>,
    pub(crate) depends_on_remove: Option<&'a [String]>,
    /// Structured recurrence rule JSON (`--recurrence`) or `Clear`
    /// (`--clear-recurrence`). The CLI accepts the same JSON object
    /// shape MCP `update_task` accepts for the typed
    /// `RecurrenceRuleArgs`; the workflow normalizes it through the
    /// shared `normalize_task_recurrence` gate.
    pub(crate) recurrence: lorvex_domain::Patch<&'a str>,
    /// Optional idempotency token. When supplied, the CLI consults the
    /// shared idempotency cache before applying the patch — a retry
    /// with the same key returns the cached response instead of
    /// re-applying the additive `tags_add` / `depends_on_add` patches.
    pub(crate) idempotency_key: Option<&'a str>,
}

impl TaskUpdateFields<'_> {
    pub(super) const fn has_any_patch(&self) -> bool {
        self.title.is_some()
            || self.body.is_set_or_clear()
            || self.ai_notes.is_set_or_clear()
            || self.status.is_some()
            || self.raw_input.is_some()
            || self.list_id.is_some()
            || self.priority.is_set_or_clear()
            || self.due_date.is_set_or_clear()
            || self.due_time.is_set_or_clear()
            || self.planned_date.is_set_or_clear()
            || self.estimated_minutes.is_set_or_clear()
            || self.recurrence.is_set_or_clear()
            || self.changes_tags()
            || self.changes_dependencies()
    }

    pub(super) const fn changes_tags(&self) -> bool {
        self.tags_set.is_some() || self.tags_add.is_some() || self.tags_remove.is_some()
    }

    pub(super) const fn changes_dependencies(&self) -> bool {
        self.depends_on_set.is_some()
            || self.depends_on_add.is_some()
            || self.depends_on_remove.is_some()
    }
}
