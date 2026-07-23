// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

//! Integration tests: export/import round-trip.
//!
//! These tests verify that a full export → import cycle preserves all data
//! categories: entities, edges, children, audit entries, and tombstones.

#[path = "export_import_roundtrip/audit_memory.rs"]
mod audit_memory;
#[path = "export_import_roundtrip/conflict_and_shadows.rs"]
mod conflict_and_shadows;
#[path = "export_import_roundtrip/empty_update_offline.rs"]
mod empty_update_offline;
#[path = "export_import_roundtrip/entity_domains.rs"]
mod entity_domains;
#[path = "export_import_roundtrip/focus_schedule.rs"]
mod focus_schedule;
#[path = "export_import_roundtrip/full_roundtrip.rs"]
mod full_roundtrip;
#[path = "export_import_roundtrip/support.rs"]
mod support;
