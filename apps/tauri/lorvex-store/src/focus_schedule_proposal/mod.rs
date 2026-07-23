//! Shared Focus Schedule proposal planner.
//!
//! The MCP server and CLI both expose a "propose schedule" read path. Keep the
//! packing algorithm here so their slot/block semantics cannot drift.
//!
//! Module layout:
//! - [`types`] — public DTOs returned to callers (FocusSchedule{Proposal,
//!   Slot, Block, Task, WorkingHours}).
//! - [`time_utils`] — minute-of-day arithmetic + the private `EventRange`
//!   span and `make_event_block` builder used by the packer.
//! - [`queries`] — SQL loaders for candidate tasks and the working-hours
//!   preference.
//! - [`proposal`] — the public `propose_focus_schedule` orchestrator and
//!   private `ProposalState` packing state machine.

mod proposal;
mod queries;
mod time_utils;
mod types;

pub use proposal::propose_focus_schedule;
pub use types::{
    FocusScheduleBlock, FocusScheduleProposal, FocusScheduleSlot, FocusScheduleTask,
    FocusScheduleWorkingHours,
};
