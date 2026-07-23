//! Per-concern effect modules for the canonical single-row `update_task`
//! mutation.
//!
//! `apply_single_update_in_savepoint` orchestrates these submodules in a
//! fixed order; each module owns its slice of [`TaskUpdateSyncEffects`]
//! (defined in [`super::mutation`]) and the SQL writes that produce it:
//!
//! * [`preparation`] — patch normalization, validation, the
//!   `PreparedTaskUpdate` shape every downstream effect reads.
//! * [`row`] — primary `tasks` row UPDATE.
//! * [`tags`] — task-tag edge add/remove.
//! * [`dependencies`] — dependency edge replace + cycle precheck.
//! * [`recurrence`] — recurrence skeleton + EXDATE-preserving patch.
//! * [`status`] — status transition + lifecycle plan collection.

pub(super) mod dependencies;
pub(super) mod preparation;
pub(super) mod recurrence;
pub(super) mod row;
pub(super) mod status;
pub(super) mod tags;
