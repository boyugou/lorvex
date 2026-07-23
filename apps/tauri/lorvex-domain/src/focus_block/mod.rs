//! Typed `focus_schedule_blocks.block_type` enum.
//!
//! Every reader / writer of `focus_schedule_blocks.block_type`
//! routes through this closed enum so the dispatch stays exhaustive
//! across the Tauri app, the MCP server, the sync apply pipeline,
//! and the storage layer. The SQL CHECK on the column does not
//! constrain the value, so a future variant added on the writer side
//! would silently land in the table; without an enum, every reader's
//! `_ => {}` arm would drop the new variant.
//!
//! The MCP server's `server_contract::ScheduleBlockType` covers a
//! subset (`Task`, `Buffer`) — that enum is the wire shape of the
//! `propose_daily_schedule` / `save_focus_schedule` MCP tools, where
//! the assistant cannot author `Event` blocks (those are imported
//! from native calendars). The Tauri-facing surface accepts all three
//! because the renderer surfaces native-calendar events alongside
//! task / buffer blocks, so this enum is the strict superset.

/// Wire form of `focus_schedule_blocks.block_type`. The `as_str()`
/// values match what the SQL writers and the apply pipeline persist.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FocusBlockType {
    /// User-authored work block tied to a `task_id` (FK into `tasks`).
    Task,
    /// Break / transition slot between work blocks. No `task_id`.
    Buffer,
    /// Calendar event imported from a native subscription (mirrors the
    /// underlying calendar event by `event_id`). No `task_id`.
    Event,
}

impl FocusBlockType {
    /// Wire form (matches the historical SQL bind values).
    pub const fn as_str(self) -> &'static str {
        match self {
            FocusBlockType::Task => "task",
            FocusBlockType::Buffer => "buffer",
            FocusBlockType::Event => "event",
        }
    }

    /// Strict parse — returns `None` for any value not in the closed
    /// set. Callers persisting from external input should treat
    /// `None` as a rejection (validation error / drop the row), not
    /// silently coerce to a default; the previous string-typed shape
    /// would have happily rendered a `"holiday"` block as a no-op
    /// because every reader's match used a wildcard fall-through.
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "task" => Some(FocusBlockType::Task),
            "buffer" => Some(FocusBlockType::Buffer),
            "event" => Some(FocusBlockType::Event),
            _ => None,
        }
    }

    /// `true` when the block requires a non-empty `task_id` to be
    /// persisted. Centralizes the contract that lived as
    /// `block_type == "task"` checks scattered across query/insert
    /// helpers.
    pub const fn requires_task_id(self) -> bool {
        matches!(self, FocusBlockType::Task)
    }
}

impl std::fmt::Display for FocusBlockType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests;
