// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

//! Integration tests for the lorvex-store migration framework.
//!
//! These tests verify that:
//! - A fresh in-memory database can apply the consolidated schema.
//! - All tables, columns, and indexes are created correctly.
//! - Applying migrations twice is idempotent.
//!
//! Regression families live under the sibling `migrations/` module
//! directory so this root stays a composition boundary.

#[path = "migrations/bool_columns.rs"]
mod bool_columns;
#[path = "migrations/column_pins.rs"]
mod column_pins;
#[path = "migrations/constraints.rs"]
mod constraints;
#[path = "migrations/indexes.rs"]
mod indexes;
#[path = "migrations/schema_inventory.rs"]
mod schema_inventory;
#[path = "migrations/support.rs"]
mod support;
#[path = "migrations/table_rebuild.rs"]
mod table_rebuild;
