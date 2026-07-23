//! Process-wide maintenance modules: disk-full circuit breaker, HLC seed
//! recovery, setup-status snapshot, and startup integrity sweeps.
//!
//! Grouped here so the crate root surfaces a smaller, more navigable set
//! of subtrees instead of four parallel siblings (#3372).

pub mod disk_full;
pub mod hlc_seed;
pub mod setup_status;
pub mod startup;
