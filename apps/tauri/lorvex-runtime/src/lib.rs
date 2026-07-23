// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-runtime` — shared operating model for every Lorvex surface.
//!
//! Holds the cross-surface runtime concerns that the Tauri app, MCP
//! server, CLI, and sync layer all consume:
//!
//! - **DB locator** — single source of truth for resolving the SQLite
//!   path (per-OS conventions + override env vars) and capturing
//!   diagnostics for surfacing in the UI.
//! - **Device identity** — stable per-install device id used by sync
//!   envelopes and HLC version stamps.
//! - **MCP host authority + sync leases** — coordination primitives
//!   that keep sync apply / outbox enqueue serial across surfaces.
//! - **Capability profiles** — feature-flag matrix per surface
//!   (`SurfaceCapabilities`) so callers can ask "is FTS available
//!   here?" without re-reading config.
//! - **Rate limiting + local change sequencing** — runtime helpers
//!   that gate write throughput and provide the monotonic
//!   `local_change_seq` used by the outbox.

pub(crate) mod capabilities;
pub(crate) mod db_locator;
pub mod device_identity;
pub mod error;
pub(crate) mod jitter_rng;
pub mod local_state;
pub mod mcp_authority;
pub mod rate_limit;
pub mod surface_hlc;
pub mod sync_checkpoints;
pub mod sync_owner;
#[cfg(any(test, feature = "test-support"))]
pub mod test_support;

pub use capabilities::{capabilities_for, SurfaceCapabilities, SurfaceProfile};
pub use db_locator::{
    resolve_db_location_details, resolve_db_path, take_db_location_diagnostics, DbLocationDetails,
    DbLocationDiagnostic, DbLocationDiagnosticCode, DbPathSource,
};
// Only exposed when `test-support` feature is on (or in the crate's
// own tests) so production binaries cannot reach the unsafe env
// mutation helper.
pub use device_identity::{device_id_to_hlc_suffix, get_or_create_device_id};
pub use error::{RuntimeError, RuntimeResult};
pub use jitter_rng::JitterRng;
pub use local_state::{bump_local_change_seq, read_local_change_seq};
pub use mcp_authority::{
    claim_mcp_host_authority, classify_mcp_host, detect_cli_installation, get_mcp_host_authority,
    path_is_executable_binary, reclaim_app_mcp_host_authority_when_cli_missing,
    McpHostAuthorityKind, McpHostKind, McpHostWriteOutcome,
};
pub use rate_limit::{
    WarnSignal, WriteRateDecision, WriteRateLimitState, HARD_CAPACITY, SOFT_CAPACITY,
};
pub use surface_hlc::{SurfaceHlcError, SurfaceHlcGuard, SurfaceHlcInitOutcome, SurfaceHlcRuntime};
pub use sync_checkpoints::{
    clear as sync_checkpoint_clear, get as sync_checkpoint_get, set as sync_checkpoint_set,
    KEY_DEVICE_ID, KEY_FULL_SYNC_SEEDED, KEY_LAST_ERROR, KEY_LAST_SUCCESS_AT, KEY_RESEED_REQUIRED,
};
pub use sync_owner::{
    current_sync_owner, process_owner_id, release_sync_owner, renew_sync_owner_now,
    try_acquire_sync_owner_now, try_acquire_sync_owner_with_guard_now, LeaseReleaseFn,
    ReleasePanicHook, SyncOwnerLease, SyncOwnerLeaseGuard, MAX_LEASE_TTL_MS,
};
#[cfg(any(test, feature = "test-support"))]
pub use test_support::with_db_path_env_for_test;
