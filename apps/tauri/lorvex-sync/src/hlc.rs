//! Process-wide HLC observer hook.
//!
//! Historical context: this module owned the observer slot
//! directly. The slot was moved into `lorvex_domain::hlc_observer` so
//! lower-layer lifecycle ops (notably `lorvex_workflow::
//! lifecycle::cancel`'s `cancel_series` HLC mint) can also call
//! `observe_local_event` without violating crate-boundary rules
//! (`lorvex-store` sits below `lorvex-sync` and cannot depend on it).
//!
//! Re-exporting the canonical types here keeps every existing
//! `lorvex_sync::hlc::*` call site (Tauri startup, MCP startup, CLI
//! startup, integration tests, merge-site `debug_assert!`s) working
//! unchanged.

pub use lorvex_domain::hlc_observer::{
    install_noop_observer_for_tests, observe_local_event, production_observer_is_installed,
    set_local_event_observer, with_temporary_observer, SetObserverOutcome,
};
