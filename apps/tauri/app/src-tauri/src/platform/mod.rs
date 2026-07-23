//! Centralized platform-specific behavior.
//!
//! Each submodule owns one cross-platform concern. Inside each submodule,
//! `#[cfg]` selects the platform-appropriate implementation. Callers
//! import from `crate::platform::*` without needing platform knowledge.

#[cfg(target_os = "windows")]
pub(crate) mod app_user_model_id;
pub(crate) mod badge;
pub(crate) mod biometrics;
pub(crate) mod close_policy;
#[cfg(target_os = "windows")]
pub(crate) mod com_apartment;
pub(crate) mod linux_calendar;
pub(crate) mod notification_actions;
pub(crate) mod notification_dispatcher;
pub(crate) mod notification_strings;
pub(crate) mod paths;
#[cfg(any(target_os = "linux", target_os = "windows", test))]
pub(crate) mod provider_scope_state;
#[cfg(any(target_os = "windows", test))]
pub(crate) mod provider_time;
pub(crate) mod spotlight;
pub(crate) mod window_management;
pub(crate) mod windows_calendar;
#[cfg(target_os = "windows")]
pub(crate) mod winrt_async;
