//! MCP memory tools, split by concern.
//!
//! The original 584-line `server_memory.rs` mixed write, delete, read,
//! history/restore, the lock gate, and preview helpers. Each concern
//! lives in a sibling module here; this hub re-exports the public surface.

mod delete;
mod gate;
mod history;
mod key;
mod read;
mod write;

pub(crate) use delete::delete_memory;
pub(crate) use history::{get_memory_history, restore_memory_revision};
pub(crate) use read::{read_memory, read_memory_session_summary};
pub(crate) use write::write_memory;

#[cfg(test)]
mod tests;
