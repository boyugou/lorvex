//! Merge / redirect logic for payload shadows.
//!
//! Two top-level entry points:
//!
//! - [`merge_shadow_into_redirect`] consolidates a loser shadow row into
//!   the redirect target, gated by a SAVEPOINT-protected CAS so a
//!   concurrent winner update cannot be silently clobbered.
//! - [`merge_payload_with_shadow`] reconstructs the live payload by
//!   overlaying the locally-known fields onto the shadow's preserved
//!   forward-compat keys, with a cross-type-redirect detector that
//!   refuses to cross-pollinate loser-schema fields into a winner-schema
//!   re-emit.
//!
//! The owned-keys allowlist `owned_keys_for_entity` lives in the
//! sibling module [`super::owned_keys`]; both `merge_payload_with_shadow`
//! here and the shadow-write path in [`super::crud`] consult it.
//!
//! This module is split into per-concern siblings:
//!
//! - [`redirect`] — `merge_shadow_into_redirect` + the row-level
//!   `merge_shadow_rows` LWW combiner it drives.
//! - [`single`] — `merge_payload_with_shadow` (per-row unindexed path).
//! - [`batch`] — [`ShadowIndex`] + `merge_payload_with_shadow_indexed`
//!   (export pipeline bulk path).
//! - [`helpers`] — small shared utilities (cross-type redirect probe,
//!   shared finalize step, `parse_json_object`).

mod batch;
mod helpers;
mod redirect;
mod single;

pub use batch::{merge_payload_with_shadow_indexed, ShadowIndex};
pub use redirect::merge_shadow_into_redirect;
pub use single::merge_payload_with_shadow;
