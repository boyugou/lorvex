//! Typed errors surfaced by [`stamp_entity_version`](super::stamp_entity_version).

#[derive(Debug)]
pub enum VersionStampError {
    Sqlite(rusqlite::Error),
    InvalidCompositeEntityId {
        entity_type: String,
        entity_id: String,
    },
    UnsupportedEntityType(String),
    /// The entity row was not found — caller must not enqueue a sync
    /// envelope for an entity whose local version column would remain
    /// stale (local LWW checks would then read the stale version, letting
    /// intermediate-version remote envelopes incorrectly win).
    EntityNotFound {
        entity_type: String,
        entity_id: String,
    },
    /// a concurrent writer already stamped a strictly
    /// newer version on the row. The caller MUST NOT enqueue an
    /// envelope at the requested (now superseded) version — its
    /// payload reflects pre-superseding state that no longer matches
    /// the row, and the resulting envelope would carry an HLC that
    /// disagrees with the row's `version` column. Re-read the row
    /// and emit at the latest stamped version, or abort the
    /// mutation entirely.
    Superseded {
        entity_type: &'static str,
        entity_id: String,
        existing_version: String,
    },
}

impl From<rusqlite::Error> for VersionStampError {
    fn from(error: rusqlite::Error) -> Self {
        Self::Sqlite(error)
    }
}

impl std::fmt::Display for VersionStampError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Sqlite(error) => write!(f, "{error}"),
            Self::InvalidCompositeEntityId {
                entity_type,
                entity_id,
            } => write!(
                f,
                "invalid composite entity id for {entity_type}: {entity_id}"
            ),
            Self::UnsupportedEntityType(entity_type) => {
                write!(
                    f,
                    "unsupported entity type for version stamping: {entity_type}"
                )
            }
            Self::EntityNotFound {
                entity_type,
                entity_id,
            } => {
                write!(
                    f,
                    "entity not found for version stamping: {entity_type}:{entity_id}"
                )
            }
            Self::Superseded {
                entity_type,
                entity_id,
                existing_version,
            } => {
                write!(
                    f,
                    "version stamping superseded for {entity_type}:{entity_id} \
                     (existing version {existing_version} is newer than attempted stamp)"
                )
            }
        }
    }
}

impl std::error::Error for VersionStampError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Sqlite(error) => Some(error),
            _ => None,
        }
    }
}
