mod diagnostics;
mod main_window;

pub(super) use diagnostics::append_window_restore_log;
#[cfg(target_os = "macos")]
pub(super) use diagnostics::{append_window_restore_trace, capture_window_restore_snapshot};
#[cfg(target_os = "macos")]
pub(super) use main_window::hard_recover_main_window;
pub(crate) use main_window::restore_main_window_direct;
pub(super) use main_window::restore_main_window_once;
