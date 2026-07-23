#[derive(Debug, Clone, PartialEq, Eq, super::Serialize, super::Deserialize)]
pub(crate) struct FilesystemBridgeDiagnostic {
    pub(crate) source: String,
    pub(crate) message: String,
    pub(crate) details: Option<String>,
    pub(crate) level: String,
}

impl FilesystemBridgeDiagnostic {
    pub(crate) fn warn(
        source: impl Into<String>,
        message: impl Into<String>,
        details: impl Into<String>,
    ) -> Self {
        Self {
            source: source.into(),
            message: message.into(),
            details: Some(details.into()),
            level: "warn".to_string(),
        }
    }
}

pub(crate) fn persist_filesystem_bridge_diagnostic(
    conn: &rusqlite::Connection,
    diagnostic: &FilesystemBridgeDiagnostic,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        &diagnostic.source,
        &diagnostic.message,
        diagnostic.details.clone(),
        Some(diagnostic.level.clone()),
    );
}

pub(crate) fn persist_filesystem_bridge_diagnostics(
    conn: &rusqlite::Connection,
    diagnostics: &[FilesystemBridgeDiagnostic],
) {
    for diagnostic in diagnostics {
        persist_filesystem_bridge_diagnostic(conn, diagnostic);
    }
}
