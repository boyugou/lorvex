//! Sync-owner lease tests, split by domain so a failing assertion
//! localizes to a single concern (acquire/release semantics, RAII
//! guard, panic safety, TTL validation, renewal).

mod acquire;
mod guard;
mod panic_safety;
mod renew;
mod support;
mod ttl_validation;
