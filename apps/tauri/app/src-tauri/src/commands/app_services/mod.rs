//! `app_services` — top-level Tauri IPC entry points that don't
//! belong to a single domain crate.
//!
//!   * `system` — auto-update probe and biometrics bridge.

pub(crate) mod system;
