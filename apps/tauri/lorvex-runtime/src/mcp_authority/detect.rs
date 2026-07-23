use std::path::{Path, PathBuf};

pub fn path_is_executable_binary(path: &Path) -> bool {
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };
    if !metadata.is_file() {
        return false;
    }
    if metadata.len() == 0 {
        return false;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        // At least one of user/group/other execute bits must be set.
        const ANY_EXEC: u32 = 0o111;
        if metadata.permissions().mode() & ANY_EXEC == 0 {
            return false;
        }
    }

    true
}

/// Check if a CLI binary exists at a well-known location.
///
/// returns the first candidate that is a non-empty, executable
/// regular file. Bare `Path::exists()` was racy (uninstall-mid-check) and
/// allowed 0-byte placeholders to shadow real installs.
pub fn detect_cli_installation() -> Option<PathBuf> {
    cli_binary_candidates()
        .into_iter()
        .find(|p| path_is_executable_binary(p))
}

pub(super) fn cli_binary_candidates() -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    // Homebrew — Apple Silicon
    candidates.push(PathBuf::from("/opt/homebrew/bin/lorvex"));
    // Homebrew — Intel / standard Unix
    candidates.push(PathBuf::from("/usr/local/bin/lorvex"));
    // Linux standard
    candidates.push(PathBuf::from("/usr/bin/lorvex"));
    // Cargo install
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join(".cargo/bin/lorvex"));
    }

    // XDG-style user bin paths. Many users install via
    // `cargo install --path ...` to `$XDG_BIN_HOME` (or its fallback
    // `$HOME/.local/bin`). The earlier list omitted both, so the doctor
    // mistakenly told those users no CLI was installed.
    if let Some(xdg_bin) = std::env::var_os("XDG_BIN_HOME") {
        candidates.push(PathBuf::from(xdg_bin).join("lorvex"));
    }
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join(".local/bin/lorvex"));
    }

    // Windows — check both NSIS install location and direct install.
    // `dirs::data_local_dir()` reads the redirected `%LOCALAPPDATA%`
    // (per prefer it over `home.join("AppData")`,
    // which ignores user-redirected AppData paths).
    #[cfg(target_os = "windows")]
    if let Some(local_app_data) = dirs::data_local_dir() {
        // NSIS default: AppData\Local\Programs\Lorvex\Lorvex.exe
        candidates.push(
            local_app_data
                .join("Programs")
                .join("Lorvex")
                .join("Lorvex.exe"),
        );
        // Alternative: AppData\Local\Lorvex\lorvex.exe
        candidates.push(local_app_data.join("Lorvex").join("lorvex.exe"));
    }

    candidates
}
