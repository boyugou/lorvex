//! Typed key constants for [`MutationOutput`](crate::mutation::MutationOutput)
//! extras.
//!
//! `MutationOutput` carries a JSON side-channel each descriptor uses to
//! surface follow-up values (memory revision ids, freshly-minted HLC
//! versions, post-row JSON, …) back to the surface adapter that wraps
//! the orchestrator.
//!
//! ## Namespacing rule
//!
//! Keys MUST be `"<entity_kind>:<field>"`. The entity kind matches the
//! `lorvex_domain::EntityKind` discriminator (lower-case singular,
//! e.g. `"memory"`, `"preference"`, `"task"`); the field is the
//! descriptor-defined slot inside that entity. Two examples:
//!
//! ```text
//!   memory:revision_id      // memory_revisions.revision_id
//!   memory:version          // memory.version (HLC stamp)
//!   preference:version      // preferences.version (HLC stamp)
//! ```
//!
//! The namespacing rule guards against silent collisions: a bare key
//! like `"version"` would mean the preference HLC in one descriptor
//! and the memory-revision HLC in another, and a future descriptor
//! touching both would clobber one with the other.
//!
//! New descriptors that introduce a side-channel value MUST add the
//! corresponding [`MutationExtraKey`] constant in this file. Reusing an
//! existing constant is encouraged — the same key shape across
//! descriptors keeps the audit funnel narrow.
//!
//! ## Typed key + private map
//!
//! The map exposed on `MutationOutput` is private; access flows
//! through `MutationOutput::set_extra` / `get_extra` / `take_extra`,
//! all of which take a [`MutationExtraKey`]. Bare-string
//! `extra.insert("version", v)` calls do not compile: there is no
//! `&str` overload, and the [`MutationExtraKey`] constructor is
//! crate-private, so the static instances declared below are the
//! single source of valid keys.

/// Newtype wrapper around the namespaced `<entity>:<field>` key string
/// the descriptor uses when stamping or reading a
/// [`MutationOutput`](crate::mutation::MutationOutput) extra. The
/// wrapper is intentionally constructor-only — the inner `String` is
/// private — so the canonical typed constants declared in this module
/// are the single source of valid keys.
///
/// New descriptors should add their key as a `pub static` instance
/// rather than calling [`MutationExtraKey::new`] inline at the call
/// site; the static-instance pattern keeps the namespacing rule above
/// auditable from this single file.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct MutationExtraKey(String);

impl MutationExtraKey {
    /// Mint a new key from an entity kind + field slot. The resulting
    /// string is `"{entity}:{field}"` per the namespacing rule.
    ///
    /// Scoped to `pub(crate)` so only the static constants declared in
    /// this module can mint keys. External crates must import a
    /// `pub static` instance — they cannot fabricate a fresh namespace
    /// at the call site.
    #[must_use]
    pub(crate) fn new(entity: &str, field: &str) -> Self {
        Self(format!("{entity}:{field}"))
    }

    /// Borrow the inner `<entity>:<field>` string. The map storage on
    /// [`MutationOutput`] is keyed on owned `String`s, so the wrapper
    /// produces the canonical `&str` lookup form here.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for MutationExtraKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

use std::sync::LazyLock;

/// HLC version string the `write_memory` descriptor stamps onto a
/// memory + memory_revision pair. Read by the MCP response builder to
/// patch the post-mutation `version` field onto the JSON return.
pub static MEMORY_VERSION: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("memory", "version"));

/// `memory_revisions.revision_id` of the child revision row created
/// alongside a memory upsert. Read by the MCP response builder so the
/// IPC surface can echo the new revision id back to the caller without
/// a second SELECT.
pub static MEMORY_REVISION_ID: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("memory", "revision_id"));

/// Post-mutation `read::TaskRow` JSON snapshot the CLI task-write
/// descriptors (`append_to_task_body`, `set_task_ai_notes`, recurrence
/// exception add/remove) stamp inside `apply` so the surface adapter
/// reconstructs the typed row via `serde_json::from_value` instead of
/// paying for a second SELECT against the outer connection after
/// commit. Reading from the extra map gives the canonical in-tx
/// post-stamp row; a post-commit reload could otherwise see
/// peer-arrived updates committed between the local tx and the read.
pub static TASK_ROW: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("task", "row"));

/// Checklist-item relation sync payloads emitted by task checklist
/// descriptors. Read by MCP after the parent task audit row is
/// finalized so child task_checklist_item envelopes stay attached to
/// the same semantic task mutation.
pub static TASK_CHECKLIST_ITEM_SYNC_CHANGES: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("task", "checklist_item_sync_changes"));

/// Reminder IDs shifted as a child side effect of a parent task
/// deferral. MCP reads this after the parent task audit row is
/// finalized and enqueues task_reminder upserts for the moved rows.
pub static TASK_SHIFTED_REMINDER_IDS: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("task", "shifted_reminder_ids"));

/// Whether a task-calendar-event link upsert actually changed the edge row.
/// MCP reads this to preserve the legacy no-op behavior: stale/no-op upserts
/// still return the current link row but do not emit another audit/outbox row.
pub static TASK_CALENDAR_EVENT_LINK_APPLIED: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("task_calendar_event_link", "applied"));

/// Applied task-calendar-event link rows from a batch upsert. MCP reads this
/// to emit one audit/outbox row per edge that actually changed, while keeping
/// stale/no-op edges out of the changelog.
pub static TASK_CALENDAR_EVENT_LINK_APPLIED_ROWS: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("task_calendar_event_link", "applied_rows"));

/// Edge tombstone payloads captured while deleting a calendar event. MCP reads
/// this after the parent delete has applied so cascade edge DELETE envelopes can
/// preserve the pre-delete task_calendar_event_links snapshots.
pub static CALENDAR_EVENT_DELETE_EDGE_TOMBSTONES: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("calendar_event", "delete_edge_tombstones"));

/// Response payload returned by the MCP `rename_tag` surface. The primary
/// mutation after-state remains the post-rename tag row for audit; this extra
/// preserves the command's richer `{old_name,new_name,tasks_updated,task_ids}`
/// response shape.
pub static TAG_RENAME_RESPONSE: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("tag", "rename_response"));

/// Relation/tag/task sync actions emitted as side effects of MCP `rename_tag`.
/// The descriptor captures exact delete snapshots in-tx; the MCP finalizer
/// enqueues them after the skip-sync parent audit row.
pub static TAG_RENAME_SYNC_ACTIONS: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("tag", "rename_sync_actions"));

/// Public response payload returned by MCP `complete_habit`. The audit
/// after-state carries the full `habit_completions` row including `version`;
/// the response keeps the public `HabitCompletion` shape.
pub static HABIT_COMPLETION_RESPONSE: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("habit_completion", "response"));

/// Completion tombstone payloads captured while deleting a habit. MCP reads
/// this after the parent delete has applied so cascade completion DELETE
/// envelopes preserve the pre-delete `habit_completions` snapshots.
pub static HABIT_DELETE_COMPLETION_TOMBSTONES: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("habit", "delete_completion_tombstones"));

/// Reminder-policy tombstone payloads captured while deleting a habit. MCP
/// reads this after the parent delete has applied so cascade policy DELETE
/// envelopes preserve the pre-delete `habit_reminder_policies` snapshots.
pub static HABIT_DELETE_REMINDER_POLICY_TOMBSTONES: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("habit", "delete_reminder_policy_tombstones"));

/// HLC version string the `set_preference` descriptor mints inside its
/// `apply` body. Read by the CLI surface adapter so it can pass the
/// fresh version into the outbox enqueue + audit log without a second
/// HLC mint (which would produce a lex-inconsistent envelope vs the
/// row that just landed).
pub static PREFERENCE_VERSION: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("preference", "version"));

/// Pre-delete `EntitySnapshot` captured by the Tauri `delete_list`
/// descriptor inside `apply` so the surface adapter can mint the
/// per-row Undo token after the row is wiped. The Tauri surface
/// stamps a JSON-encoded `EntitySnapshot` here and the IPC handler
/// passes it to `build_undo_token` for the toast affordance.
pub static LIST_DELETE_UNDO_SNAPSHOT: LazyLock<MutationExtraKey> =
    LazyLock::new(|| MutationExtraKey::new("list", "delete_undo_snapshot"));
