//! Typed input for `lorvex_workflow::task_update::update_task`.
//!
//! Mirrors the MCP `UpdateTaskArgs` field set so every consumer surface
//! (MCP, Tauri, CLI, sync apply) speaks the same patch shape. Every
//! nullable scalar field is [`Patch<T>`] so the three states (`Unset`
//! = not in patch, `Clear` = explicit null, `Set(value)` = new value)
//! carry cleanly through serde, validation, and the SQL writer.
//!
//! `recurrence` accepts a [`serde_json::Value`] because the canonical
//! recurrence rule is lowered to JSON upstream of this layer
//! (`mcp-server` converts its typed `RecurrenceRuleArgs`; Tauri
//! passes the structured object directly). The shared
//! [`lorvex_domain::validation::normalize_task_recurrence`] gate runs
//! during apply.
//!
//! ## Why the set-style fields stay `Option<Vec<String>>`
//!
//! `tags_set` / `tags_add` / `tags_remove` and
//! `depends_on` / `depends_on_add` / `depends_on_remove` are
//! deliberately `Option<Vec<String>>` instead of `Patch<Vec<String>>`.
//!
//! These are set-mutating operations, not nullable scalars. The wire
//! contract has exactly two states:
//!
//! - **absent / `null`** → `None` → no-op (don't touch this relation)
//! - **`[...]` (any array, including `[]`)** → `Some(vec)` → apply the
//!   operation with this item list
//!
//! For the `_set`/`depends_on` replace variants, `Some(vec![])` *is*
//! the clear semantic ("replace the set with the empty set"). For the
//! `_add`/`_remove` variants, `Some(vec![])` is a no-op (add/remove
//! zero items). There is no third state to encode: `Patch::Clear` and
//! `Patch::Set(vec![])` would be semantically identical for the replace
//! fields, and both would be no-ops for the add/remove fields. The
//! Patch shape would add wire surface (`null` becomes distinguishable
//! from `[]`) for zero meaning.
//!
//! The neighbouring `Patch<String>` / `Patch<u8>` fields earn the
//! third state because the underlying SQL columns are nullable —
//! `Patch::Clear` writes SQL NULL, distinct from leaving the column
//! alone. Set-typed fields write into junction tables (`task_tags`,
//! `task_dependencies`), where "clear" means deleting rows, which is
//! already expressible as "set to empty".

use lorvex_domain::Patch;
use serde_json::Value;

/// Single-item task update patch. Field names match MCP
/// `UpdateTaskArgs` exactly so the cross-surface contract test can
/// verify the boundary stays in lockstep.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskUpdateInput {
    pub id: String,
    /// Three-state patch (`Unset` / `Clear` / `Set(value)`). `tasks.title`
    /// is NOT NULL in the schema, so the preparation gate rejects
    /// `Patch::Clear` with a validation error; surface adapters that
    /// cannot express clearing project `Some/None` onto `Set/Unset`.
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub title: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub body: Patch<String>,
    /// Three-state patch. `raw_input` is nullable in the schema, so the
    /// preparation gate accepts `Patch::Clear` (writes SQL NULL).
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub raw_input: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub ai_notes: Patch<String>,
    /// Three-state patch. `tasks.status` is NOT NULL with a closed-set
    /// allow-list (`open|completed|cancelled|someday`), so the
    /// preparation gate rejects `Patch::Clear` with a validation error.
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub status: Patch<String>,
    /// Three-state patch. `tasks.list_id` is NOT NULL (every task must
    /// belong to a real list), so the preparation gate rejects
    /// `Patch::Clear` with a validation error.
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub list_id: Patch<String>,
    /// Replace the full tag set. `None` = no-op; `Some(vec![])` clears
    /// every tag. Mutually exclusive with `tags_add` / `tags_remove`.
    /// Two-state by design — see module docstring for why this is
    /// `Option<Vec<String>>` rather than `Patch<Vec<String>>`.
    #[serde(default)]
    pub tags_set: Option<Vec<String>>,
    /// Append tags without touching the rest of the set. `None` and
    /// `Some(vec![])` are both no-ops. Mutually exclusive with
    /// `tags_set`.
    #[serde(default)]
    pub tags_add: Option<Vec<String>>,
    /// Remove tags without touching the rest of the set. `None` and
    /// `Some(vec![])` are both no-ops. Mutually exclusive with
    /// `tags_set`.
    #[serde(default)]
    pub tags_remove: Option<Vec<String>>,
    /// Three-state patch (`Unset` / `Clear` / `Set(0..=4)`). MCP exposes
    /// the wire shape as `Option<u8>` because the public assistant
    /// contract does not allow clearing priority via update_task; its
    /// adapter maps `Some(n) → Set(n)` and `None → Unset`. Tauri does
    /// allow clearing priority (renderer posts `priority: null`), so
    /// the typed input keeps the three-state shape and surface adapters
    /// project into it.
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub priority: Patch<u8>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub due_date: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub due_time: Patch<String>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub estimated_minutes: Patch<u32>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub recurrence: Patch<Value>,
    /// Replace the full dependency edge set. `None` = no-op;
    /// `Some(vec![])` clears every edge. Mutually exclusive with
    /// `depends_on_add` / `depends_on_remove` — mirrors the tag-patch
    /// precedence rule. Two-state by design — see module docstring for
    /// why this is `Option<Vec<String>>` rather than
    /// `Patch<Vec<String>>`.
    #[serde(default)]
    pub depends_on: Option<Vec<String>>,
    /// Append dependency edges without touching the rest of the set.
    /// `None` and `Some(vec![])` are both no-ops. Mutually exclusive
    /// with `depends_on`.
    #[serde(default)]
    pub depends_on_add: Option<Vec<String>>,
    /// Remove dependency edges without touching the rest of the set.
    /// `None` and `Some(vec![])` are both no-ops. Mutually exclusive
    /// with `depends_on`.
    #[serde(default)]
    pub depends_on_remove: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub planned_date: Patch<String>,
}

impl TaskUpdateInput {
    /// The canonical field set this input accepts. Used by the
    /// repo-governance contract test that pins Tauri and MCP to the
    /// same wire shape.
    pub const FIELDS: &'static [&'static str] = &[
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "tags_set",
        "tags_add",
        "tags_remove",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        "depends_on",
        "depends_on_add",
        "depends_on_remove",
        "planned_date",
    ];
}
