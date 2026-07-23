//! User-settings Tauri commands: typed preference get / set / reset
//! plus the small bag of derived settings reads (default sync
//! backend, default filesystem-bridge root path).
//!
//! Source: refactor for #3277 — `preferences.rs` and its companion
//! directory at the `commands/` root were folded under this
//! `settings/` namespace.

pub(crate) mod preferences;
