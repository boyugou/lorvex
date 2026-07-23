//! Current-focus mutations — four narrow MCP entry points, one per
//! verb. Each child module owns its own validation, idempotency cache
//! interaction, and changelog/tombstone audit shape; this `mod.rs`
//! re-exports them for the `focus::current` facade.

mod add;
mod audit;
mod clear;
mod remove;
mod set;

pub(crate) use add::add_to_current_focus;
pub(crate) use clear::clear_current_focus;
pub(crate) use remove::remove_from_current_focus;
pub(crate) use set::set_current_focus;
