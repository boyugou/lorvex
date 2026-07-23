//! Sync apply pipeline — process incoming sync envelopes against the local
//! database.
//!
//! The pipeline for each envelope:
//! 1. Check envelope `payload_schema_version` against local max.
//! 2. Check if entity is tombstoned (with redirect handling).
//! 3. Compare version (LWW via domain merge policy).
//! 4. Delegate to entity-specific handler (real SQL mutations).
//! 5. Log conflicts if the local version won.
//!
//! See spec Section 5: Root Sync Model & Merge Rules, Idempotent Apply.

mod aggregate;
mod changelog;
mod child;
mod collision;
mod conflict;
mod day_scoped;
mod device_identity;
mod dispatch;
mod edge;
mod envelope;
mod error;
mod json_helpers;
mod lww;
mod merge_hlc;
mod promote;
mod redirect;
mod tag;

pub use envelope::apply_envelope;
pub use error::{ApplyError, ApplyResult, DeferralReason};
pub use promote::promote_payload_shadows;

pub(crate) use envelope::get_local_version;
pub(crate) use lww::{
    lww_gated_delete, stamp_merge_winner_version, version_cmp, LwwRejectedDetail, LwwTieBreak,
    LwwUpsertSpec,
};
pub(crate) use redirect::remap_payload_identity_fields;

#[cfg(test)]
pub(crate) use collision::{
    check_device_identity_collision, collision_test_mutex,
    reset_device_identity_collision_guard_for_testing,
};
#[cfg(test)]
pub(crate) use error::REDIRECT_CHAIN_CAP;

#[cfg(test)]
mod tests;
