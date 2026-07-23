//! DB-path resolution result types and structured diagnostic codes.
//!
//! Pulled out of the monolithic `db_locator.rs` so the result envelope
//! (`DbLocationDetails`) and diagnostic payloads can be referenced
//! without dragging the resolver implementation surface along.

use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbPathSource {
    EnvOverride,
    PlatformDataDir,
    HomeFallback,
}

impl DbPathSource {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::EnvOverride => "env_override",
            Self::PlatformDataDir => "platform_data_dir",
            Self::HomeFallback => "home_fallback",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DbLocationDiagnosticCode {
    DbPathOverrideIgnoredRelease,
    DbPathOverrideRejectedUnc,
}

impl DbLocationDiagnosticCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::DbPathOverrideIgnoredRelease => "db_path_override_ignored_release",
            Self::DbPathOverrideRejectedUnc => "db_path_override_rejected_unc",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DbLocationDiagnostic {
    pub code: DbLocationDiagnosticCode,
    pub message: String,
    pub details: Option<String>,
    pub level: &'static str,
}

impl DbLocationDiagnostic {
    pub(super) fn warn(code: DbLocationDiagnosticCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            details: None,
            level: "warn",
        }
    }

    pub(super) fn with_details(mut self, details: impl Into<String>) -> Self {
        self.details = Some(details.into());
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DbLocationDetails {
    pub resolved_path: PathBuf,
    pub source: DbPathSource,
    pub platform_default_path: PathBuf,
    pub diagnostics: Vec<DbLocationDiagnostic>,
}
