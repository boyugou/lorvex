//! Error type for the import pipeline plus its `From`/`Display`/`Error`
//! plumbing.
//!
//! [`ImportError::DryRunRollback`] is an internal-only variant the
//! transaction body uses to short-circuit a successful dry-run preview
//! into the rollback path. It is intercepted by
//! [`super::import_from_zip_file_with_options`] and never escapes to
//! callers.

use super::types::ImportSummary;

/// Errors that can occur during import.
#[derive(Debug)]
pub enum ImportError {
    /// Operation was cancelled cooperatively by the caller.
    Cancelled,
    /// Store-layer validation/invariant/serialization failure.
    Store(crate::error::StoreError),
    /// Database query failure.
    Sql(rusqlite::Error),
    /// I/O or ZIP reading failure.
    Io(std::io::Error),
    /// ZIP library error.
    Zip(zip::result::ZipError),
    /// JSON deserialization failure.
    Json(serde_json::Error),
    /// Incompatible format version.
    IncompatibleVersion { expected: u32, found: u32 },
    /// Missing required file in the archive.
    MissingFile(String),
    /// Import payload shape or field types are invalid.
    InvalidPayload(String),
    /// Transaction cleanup failed after an import error.
    Transaction(String),
    /// Internal signal: dry-run preview completed successfully, causing
    /// the wrapping transaction to ROLLBACK. The carried summary is what
    /// the commit path would have returned. This variant never escapes
    /// [`super::import_from_zip_with_options`]; the outer code intercepts it
    /// and returns the summary as `Ok`.
    #[doc(hidden)]
    DryRunRollback(Box<ImportSummary>),
}

impl std::fmt::Display for ImportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ImportError::Cancelled => write!(f, "import cancelled"),
            ImportError::Store(e) => write!(f, "import store error: {e}"),
            ImportError::Sql(e) => write!(f, "import SQL error: {e}"),
            ImportError::Io(e) => write!(f, "import I/O error: {e}"),
            ImportError::Zip(e) => write!(f, "import ZIP error: {e}"),
            ImportError::Json(e) => write!(f, "import JSON error: {e}"),
            ImportError::IncompatibleVersion { expected, found } => {
                write!(
                    f,
                    "incompatible export format version: expected {expected}, found {found}"
                )
            }
            ImportError::MissingFile(name) => write!(f, "missing file in archive: {name}"),
            ImportError::InvalidPayload(message) => write!(f, "invalid import payload: {message}"),
            ImportError::Transaction(message) => write!(f, "{message}"),
            ImportError::DryRunRollback(_) => write!(f, "dry-run rollback (internal signal)"),
        }
    }
}

impl std::error::Error for ImportError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        // The `Cancelled` arm is pinned as a named arm even though its
        // body matches the wildcard fallthrough below — the surface
        // documents that user-initiated cancellation is a normal
        // termination path with no underlying error to surface, distinct
        // from the `_ => None` arm that catches payload-only variants.
        #[allow(clippy::match_same_arms)]
        match self {
            ImportError::Cancelled => None,
            ImportError::Store(e) => Some(e),
            ImportError::Sql(e) => Some(e),
            ImportError::Io(e) => Some(e),
            ImportError::Zip(e) => Some(e),
            ImportError::Json(e) => Some(e),
            // InvalidPayload / Transaction / DryRunRollback carry only message
            // strings, not a wrapped error type — no source to surface.
            _ => None,
        }
    }
}

impl From<rusqlite::Error> for ImportError {
    fn from(e: rusqlite::Error) -> Self {
        ImportError::Sql(e)
    }
}

impl From<std::io::Error> for ImportError {
    fn from(e: std::io::Error) -> Self {
        ImportError::Io(e)
    }
}

impl From<zip::result::ZipError> for ImportError {
    fn from(e: zip::result::ZipError) -> Self {
        ImportError::Zip(e)
    }
}

impl From<serde_json::Error> for ImportError {
    fn from(e: serde_json::Error) -> Self {
        ImportError::Json(e)
    }
}

impl From<crate::error::StoreError> for ImportError {
    fn from(e: crate::error::StoreError) -> Self {
        ImportError::Store(e)
    }
}

/// `PayloadError` originates from [`lorvex_sync_payload`] (the
/// extracted shadow-types crate, #4350). Route through `StoreError`
/// so the disk-full reclassifier inside `From<PayloadError> for
/// StoreError` runs on `Sql` variants before the import surface sees
/// them.
impl From<lorvex_sync_payload::PayloadError> for ImportError {
    fn from(e: lorvex_sync_payload::PayloadError) -> Self {
        ImportError::Store(crate::error::StoreError::from(e))
    }
}

impl From<String> for ImportError {
    fn from(message: String) -> Self {
        ImportError::Transaction(message)
    }
}
