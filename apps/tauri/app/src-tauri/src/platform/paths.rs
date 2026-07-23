//! Platform-specific default paths.
//!
//! - macOS: Home directory (provider-neutral filesystem bridge root)
//! - Windows: Documents folder
//! - Linux: Home directory
//! - Mobile: None (not applicable)

use std::path::PathBuf;

pub(crate) fn default_filesystem_bridge_root_path() -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        let home = dirs::home_dir()?;
        Some(home.join("LorvexSync"))
    }

    #[cfg(target_os = "windows")]
    {
        let docs = dirs::document_dir().or_else(dirs::home_dir)?;
        Some(docs.join("LorvexSync"))
    }

    #[cfg(target_os = "linux")]
    {
        let home = dirs::home_dir()?;
        Some(home.join("LorvexSync"))
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        None
    }
}
