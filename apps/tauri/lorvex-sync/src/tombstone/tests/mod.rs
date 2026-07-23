//! Tombstone subsystem tests — split by domain so a failing assertion
//! localizes to a single concern (basic CRUD, redirect semantics,
//! fixed/watermark GC, version monotonicity, device cursor).

mod basic;
mod device_cursor;
mod gc_fixed;
mod gc_watermark;
mod monotonicity;
mod redirect;
mod support;
