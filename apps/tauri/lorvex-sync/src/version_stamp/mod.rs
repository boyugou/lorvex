//! Shared entity version stamping for sync consistency.
//!
//! When a mutation is enqueued to the sync outbox, the entity's `version`
//! column must be updated to match the envelope version. Without this,
//! the local LWW check may use a stale version, causing remote changes
//! to incorrectly overwrite local edits.

mod composite;
mod error;
mod predicates;
mod simple_pk;
mod stamp;

#[cfg(test)]
mod tests;

pub use error::VersionStampError;
pub use stamp::stamp_entity_version;

/// Pin the schema-level `version NOT NULL` invariant at the type
/// system. Every syncable entity's `version` column in
/// `lorvex-store/src/schema/001_schema.sql` is declared `NOT NULL`,
/// so the historical `OR version IS NULL` LWW guard branch in the
/// version-stamp UPDATE / SELECT paths is unreachable. Surfacing the
/// invariant as a const both (a) lets a future schema audit catch
/// drift if someone makes a `version` column nullable and (b) lets
/// reviewers grep for the canonical contract.
pub(crate) const SYNCABLE_ENTITY_VERSION_IS_NOT_NULL: bool = true;
