use crate::error::StoreError;

/// Errors that can occur during export.
#[derive(Debug)]
pub enum ExportError {
    /// Operation was cancelled cooperatively by the caller.
    Cancelled,
    /// Store-layer validation/invariant/serialization failure.
    Store(StoreError),
    /// Database query failure.
    Sql(rusqlite::Error),
    /// I/O or ZIP writing failure.
    Io(std::io::Error),
    /// ZIP library error.
    Zip(zip::result::ZipError),
    /// JSON serialization failure.
    Json(serde_json::Error),
}

impl std::fmt::Display for ExportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ExportError::Cancelled => write!(f, "export cancelled"),
            ExportError::Store(e) => write!(f, "export store error: {e}"),
            ExportError::Sql(e) => write!(f, "export SQL error: {e}"),
            ExportError::Io(e) => write!(f, "export I/O error: {e}"),
            ExportError::Zip(e) => write!(f, "export ZIP error: {e}"),
            ExportError::Json(e) => write!(f, "export JSON error: {e}"),
        }
    }
}

impl std::error::Error for ExportError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            ExportError::Cancelled => None,
            ExportError::Store(e) => Some(e),
            ExportError::Sql(e) => Some(e),
            ExportError::Io(e) => Some(e),
            ExportError::Zip(e) => Some(e),
            ExportError::Json(e) => Some(e),
        }
    }
}

impl From<rusqlite::Error> for ExportError {
    fn from(e: rusqlite::Error) -> Self {
        ExportError::Sql(e)
    }
}

impl From<StoreError> for ExportError {
    fn from(e: StoreError) -> Self {
        ExportError::Store(e)
    }
}

/// `PayloadError` originates from [`lorvex_sync_payload`] (#4350).
/// Route through `StoreError` so the disk-full reclassifier inside
/// `From<PayloadError> for StoreError` runs on `Sql` variants before
/// the export surface sees them.
impl From<lorvex_sync_payload::PayloadError> for ExportError {
    fn from(e: lorvex_sync_payload::PayloadError) -> Self {
        ExportError::Store(StoreError::from(e))
    }
}

impl From<std::io::Error> for ExportError {
    fn from(e: std::io::Error) -> Self {
        ExportError::Io(e)
    }
}

impl From<zip::result::ZipError> for ExportError {
    fn from(e: zip::result::ZipError) -> Self {
        ExportError::Zip(e)
    }
}

impl From<serde_json::Error> for ExportError {
    fn from(e: serde_json::Error) -> Self {
        ExportError::Json(e)
    }
}
