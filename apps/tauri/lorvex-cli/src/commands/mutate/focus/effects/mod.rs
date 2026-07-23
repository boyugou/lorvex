//! Focus subsystem: current focus mutations and focus schedule CRUD.
//!
//! Submodules:
//! - `current_focus` — `CurrentFocusMutation` enum, set/add/remove/clear
//!   mutations, and view loaders for the daily focus aggregate.
//! - `schedule` — focus schedule block CRUD, schedule proposal, and the
//!   apply-to-current-focus mirror that ships with `save_focus_schedule`.
//! - `outbox` — aggregate-payload outbox enqueue helpers shared by both
//!   mutation paths.
//! - `tests` — `#[cfg(test)]` integration tests covering both subsystems.

mod current_focus;
mod outbox;
mod schedule;

#[cfg(test)]
mod tests;

pub(crate) use current_focus::{
    add_to_current_focus_with_conn, clear_current_focus_with_conn, load_current_focus_view,
    load_current_focus_view_for_date, remove_from_current_focus_with_conn,
    set_current_focus_with_conn,
};
pub(crate) use schedule::{
    get_focus_schedule_with_conn, propose_focus_schedule_with_conn, save_focus_schedule_with_conn,
};
