// #3441 phase-2 collapsed the former `core/` and `loading/` test
// subdirectories into flat `core_*` / `loading_*` siblings under
// `status/` to keep `commands/` depth ≤3.
pub(super) use super::*;

mod core_deletions;
mod core_event_state;
mod core_helpers;
mod loading_cursors;
mod loading_ical_subscriptions;
mod loading_lookback;
mod loading_pending_inbox;
mod loading_retention;
mod loading_timestamps;
mod timestamps;
