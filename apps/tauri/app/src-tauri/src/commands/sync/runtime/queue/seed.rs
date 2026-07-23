//! First-time / explicit reseed of the sync outbox: walk every
//! syncable table in the local SQLite and stage an `OP_UPSERT`
//! envelope per row so the next push (filesystem bridge,
//! whatever transport is configured) sees the full local state.
//!
//! #3303 P2 split the original 738-LOC `seed.rs` into four concerns;
//! #3441 phase-2 then collapsed the resulting `seed/` directory into
//! flat `seed_*` siblings under `queue/` to keep `commands/` depth
//! ≤3. This file is the public facade re-exporting the surface used
//! by the rest of the crate.
//!
//!   * `seed_helpers` — store-backed simple payload streaming,
//!     id-delegation pumps, and aggregate-root routing helpers.
//!   * `seed_entities` — per-entity custom seeders (`seed_lists`,
//!     `seed_tasks`, `seed_preferences`, etc.)
//!     that need bespoke SQL or row-mapping logic.
//!   * `seed_orchestrator` — the public Tauri command
//!     (`seed_full_sync`), the per-class `seed_entity_in_tx`
//!     transaction wrapper that releases the writer lock between
//!     phases for #2252, and the `seed_all_entities` driver that
//!     aggregates every count into [`SeedFullSyncResult`].
//!   * `seed_tests` — the `seed_full_sync_internal` regression suite.

pub(crate) use super::seed_orchestrator::seed_full_sync_internal;
