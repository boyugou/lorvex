use std::{
    env,
    path::{Component, Path, PathBuf},
};

use serde::Deserialize;

#[derive(Debug, Clone)]
pub(crate) struct LorvexMcpServerConfig {
    pub(crate) command: String,
    pub(crate) args: Vec<String>,
    pub(crate) cwd: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RuntimeMetadata {
    installed: RuntimeMetadataInstalled,
}

#[derive(Debug, Deserialize)]
struct RuntimeMetadataInstalled {
    bundle_resource: String,
}

fn find_repo_root_from(start: &Path) -> Option<PathBuf> {
    for dir in start.ancestors() {
        let has_rust_mcp = dir.join("mcp-server").join("Cargo.toml").is_file();
        let has_tauri_app = dir
            .join("app")
            .join("src-tauri")
            .join("tauri.conf.json")
            .is_file();
        if has_rust_mcp && has_tauri_app {
            return Some(dir.to_path_buf());
        }
    }
    None
}

fn find_repo_root() -> Option<PathBuf> {
    if let Ok(cwd) = env::current_dir() {
        if let Some(root) = find_repo_root_from(&cwd) {
            return Some(root);
        }
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            if let Some(root) = find_repo_root_from(parent) {
                return Some(root);
            }
        }
    }
    None
}

fn append_binary_candidates(candidates: &mut Vec<PathBuf>, dir: &Path, stem: &str) {
    candidates.push(dir.join(stem));
    candidates.push(dir.join(format!("{stem}.exe")));
}

fn append_lorvex_binary_candidates(candidates: &mut Vec<PathBuf>, dir: &Path) {
    append_binary_candidates(candidates, dir, "lorvex-mcp-server");
}

fn normalize_path_lexically(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if !normalized.pop() {
                    normalized.push(component.as_os_str());
                }
            }
            _ => normalized.push(component.as_os_str()),
        }
    }
    normalized
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn push_unique_path(paths: &mut Vec<PathBuf>, path: PathBuf) {
    let path = normalize_path_lexically(&path);
    if !paths.iter().any(|existing| existing == &path) {
        paths.push(path);
    }
}

fn append_repo_root_candidates(candidates: &mut Vec<PathBuf>, root: &Path) {
    append_lorvex_binary_candidates(candidates, &root.join("mcp-server").join("bin"));
    append_lorvex_binary_candidates(
        candidates,
        &root.join("mcp-server").join("target").join("release"),
    );
    append_lorvex_binary_candidates(
        candidates,
        &root.join("mcp-server").join("target").join("debug"),
    );
}

fn append_executable_relative_candidates(candidates: &mut Vec<PathBuf>, exe: &Path) {
    if let Some(exe_dir) = exe.parent() {
        append_lorvex_binary_candidates(candidates, exe_dir);
        append_lorvex_binary_candidates(candidates, &exe_dir.join("mcp-server"));
        append_lorvex_binary_candidates(candidates, &exe_dir.join("..").join("Resources"));
        append_lorvex_binary_candidates(
            candidates,
            &exe_dir.join("..").join("Resources").join("mcp-server"),
        );
        append_lorvex_binary_candidates(
            candidates,
            &exe_dir
                .join("..")
                .join("Resources")
                .join("resources")
                .join("mcp-server"),
        );
    }
}

fn append_executable_relative_metadata_candidates(candidates: &mut Vec<PathBuf>, exe: &Path) {
    if let Some(exe_dir) = exe.parent() {
        for dir in [
            exe_dir.join("mcp-server"),
            exe_dir.join("..").join("Resources").join("mcp-server"),
            exe_dir
                .join("..")
                .join("Resources")
                .join("resources")
                .join("mcp-server"),
        ] {
            push_unique_path(candidates, dir.join("runtime-metadata.json"));
        }
    }
}

fn append_repo_root_metadata_candidates(candidates: &mut Vec<PathBuf>, root: &Path) {
    let dir = root
        .join("app")
        .join("src-tauri")
        .join("resources")
        .join("mcp-server");
    push_unique_path(candidates, dir.join("runtime-metadata.json"));
}

fn collect_runtime_metadata_candidates(
    repo_root: Option<&Path>,
    exe: Option<&Path>,
) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(exe) = exe {
        append_executable_relative_metadata_candidates(&mut candidates, exe);
    }
    if let Some(root) = repo_root {
        append_repo_root_metadata_candidates(&mut candidates, root);
    }
    candidates
}

fn collect_mcp_server_binary_candidates(
    repo_root: Option<&Path>,
    exe: Option<&Path>,
) -> Vec<PathBuf> {
    let mut candidates: Vec<PathBuf> = vec![];

    // Prefer bundled executable-relative paths so packaged apps do not leak
    // development-machine absolute paths into MCP config snippets.
    if let Some(exe) = exe {
        append_executable_relative_candidates(&mut candidates, exe);
    }
    if let Some(root) = repo_root {
        append_repo_root_candidates(&mut candidates, root);
    }

    candidates
}

fn relative_after_component(path: &Path, component: &str) -> Option<PathBuf> {
    let parts: Vec<_> = path.components().collect();
    let index = parts.iter().rposition(|part| {
        part.as_os_str()
            .to_string_lossy()
            .eq_ignore_ascii_case(component)
    })?;
    let mut relative = PathBuf::new();
    for part in &parts[index + 1..] {
        relative.push(part.as_os_str());
    }
    if relative.as_os_str().is_empty() {
        None
    } else {
        Some(relative)
    }
}

fn resource_root_for_metadata_path(metadata_path: &Path) -> Option<PathBuf> {
    let mut current = metadata_path.parent()?;
    loop {
        if current
            .file_name()
            .is_some_and(|name| name.to_string_lossy().eq_ignore_ascii_case("resources"))
        {
            return Some(current.to_path_buf());
        }
        current = current.parent()?;
    }
}

fn metadata_declared_binary_candidates(
    repo_root: Option<&Path>,
    metadata_path: &Path,
    bundle_resource: &str,
) -> Result<Vec<PathBuf>, String> {
    let declared = Path::new(bundle_resource);
    if declared.is_absolute() {
        return Err(format!(
            "runtime metadata contains absolute bundle_resource path: {bundle_resource}"
        ));
    }

    let mut candidates = Vec::new();
    if let Some(root) = repo_root {
        push_unique_path(&mut candidates, root.join(declared));
    }
    if let (Some(resource_root), Some(resource_relative)) = (
        resource_root_for_metadata_path(metadata_path),
        relative_after_component(declared, "resources"),
    ) {
        push_unique_path(&mut candidates, resource_root.join(resource_relative));
    }
    Ok(candidates)
}

fn resolve_runtime_metadata_binary(
    repo_root: Option<&Path>,
    metadata_path: &Path,
) -> Result<PathBuf, String> {
    let raw = std::fs::read_to_string(metadata_path).map_err(|e| {
        format!(
            "failed to read MCP runtime metadata {}: {e}",
            metadata_path.display()
        )
    })?;
    let metadata: RuntimeMetadata = serde_json::from_str(&raw).map_err(|e| {
        format!(
            "failed to parse MCP runtime metadata {}: {e}",
            metadata_path.display()
        )
    })?;
    let resolution_metadata_path = normalize_path_lexically(metadata_path);
    let candidates = metadata_declared_binary_candidates(
        repo_root,
        &resolution_metadata_path,
        &metadata.installed.bundle_resource,
    )?;
    candidates
        .into_iter()
        .find(|path| lorvex_runtime::path_is_executable_binary(path))
        .ok_or_else(|| {
            format!(
                "MCP runtime metadata {} points to a missing, empty, or non-executable binary: {}",
                metadata_path.display(),
                metadata.installed.bundle_resource
            )
        })
}

fn find_metadata_declared_mcp_server_binary(
    repo_root: Option<&Path>,
    exe: Option<&Path>,
) -> Result<Option<PathBuf>, String> {
    for metadata_path in collect_runtime_metadata_candidates(repo_root, exe) {
        if metadata_path.is_file() {
            return resolve_runtime_metadata_binary(repo_root, &metadata_path).map(Some);
        }
    }
    Ok(None)
}

fn find_heuristic_mcp_server_binary(
    repo_root: Option<&Path>,
    current_exe: Option<&Path>,
) -> Option<PathBuf> {
    collect_mcp_server_binary_candidates(repo_root, current_exe)
        .into_iter()
        .find(|path| lorvex_runtime::path_is_executable_binary(path))
}

fn find_standalone_mcp_server_binary_from(
    repo_root: Option<&Path>,
    current_exe: Option<&Path>,
) -> Result<Option<PathBuf>, String> {
    if let Some(binary) = find_metadata_declared_mcp_server_binary(repo_root, current_exe)? {
        return Ok(Some(binary));
    }
    Ok(find_heuristic_mcp_server_binary(repo_root, current_exe))
}

fn find_standalone_mcp_server_binary() -> Result<Option<PathBuf>, String> {
    let repo_root = find_repo_root();
    let current_exe = env::current_exe().ok();
    find_standalone_mcp_server_binary_from(repo_root.as_deref(), current_exe.as_deref())
}

pub(crate) fn resolve_lorvex_mcp_server_config() -> Result<LorvexMcpServerConfig, String> {
    if let Some(binary) = find_standalone_mcp_server_binary()? {
        return Ok(LorvexMcpServerConfig {
            command: binary.to_string_lossy().to_string(),
            args: vec![],
            cwd: None,
        });
    }

    Err("Cannot locate Lorvex Rust MCP server binary. Expected bundled resources or a prepared local binary at mcp-server/bin/lorvex-mcp-server. Run `npm run -w app prepare:mcp` in the repository root."
        .to_string())
}

// Audit (#3414): every `.expect(...)` / `.unwrap()` in this file lives
// inside the `#[cfg(test)]` `tests` module below — they are test-only
// fixture helpers that legitimately panic on filesystem failure inside a
// `tempfile::tempdir()` scratch directory. The production code paths
// (lines 1-333) return `Result` everywhere via `map_err` and never
// panic on IO.
#[cfg(test)]
mod tests {
    use super::*;

    fn write_runtime_metadata(path: &Path, bundle_resource: &str) {
        std::fs::create_dir_all(path.parent().expect("metadata parent")).expect("create parent");
        std::fs::write(
            path,
            format!(
                r#"{{
  "generated_at": "2026-05-01T00:00:00.000Z",
  "profile": "release",
  "source_binary": "mcp-server/target/release/lorvex-mcp-server",
  "installed": {{
    "standalone": "mcp-server/bin/lorvex-mcp-server",
    "bundle_resource": "{bundle_resource}"
  }}
}}"#
            ),
        )
        .expect("write metadata");
    }

    fn write_executable(path: &Path) {
        std::fs::create_dir_all(path.parent().expect("binary parent")).expect("create parent");
        std::fs::write(path, b"#!/bin/sh\nexit 0\n").expect("write binary");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = std::fs::metadata(path)
                .expect("binary metadata")
                .permissions();
            permissions.set_mode(0o755);
            std::fs::set_permissions(path, permissions).expect("chmod binary");
        }
    }

    fn write_unusable_binary(path: &Path) {
        std::fs::create_dir_all(path.parent().expect("binary parent")).expect("create parent");
        std::fs::write(path, b"").expect("write binary");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = std::fs::metadata(path)
                .expect("binary metadata")
                .permissions();
            permissions.set_mode(0o644);
            std::fs::set_permissions(path, permissions).expect("chmod binary");
        }
    }

    fn index_of_suffix(candidates: &[PathBuf], suffix: &str) -> usize {
        candidates
            .iter()
            .position(|path| path.ends_with(Path::new(suffix)))
            .unwrap_or_else(|| panic!("missing candidate suffix: {suffix}"))
    }

    #[test]
    fn bundled_candidates_precede_repo_candidates() {
        let repo_root = Path::new("/repo");
        let exe_path = Path::new("/Applications/Lorvex.app/Contents/MacOS/lorvex");
        let candidates = collect_mcp_server_binary_candidates(Some(repo_root), Some(exe_path));

        let bundled_index = index_of_suffix(
            &candidates,
            "Resources/resources/mcp-server/lorvex-mcp-server",
        );
        let repo_index = index_of_suffix(&candidates, "mcp-server/bin/lorvex-mcp-server");

        assert!(bundled_index < repo_index);
    }

    #[test]
    fn still_includes_repo_candidates_when_no_executable() {
        let repo_root = Path::new("/repo");
        let candidates = collect_mcp_server_binary_candidates(Some(repo_root), None);
        let repo_index = index_of_suffix(&candidates, "mcp-server/bin/lorvex-mcp-server");
        assert_eq!(repo_index, 0);
    }

    #[test]
    fn repo_metadata_candidates_exclude_generated_apple_assets() {
        let repo_root = Path::new("/repo");
        let candidates = collect_runtime_metadata_candidates(Some(repo_root), None);

        assert_eq!(
            candidates,
            vec![repo_root
                .join("app")
                .join("src-tauri")
                .join("resources")
                .join("mcp-server")
                .join("runtime-metadata.json")]
        );
    }

    #[test]
    fn metadata_resolution_prefers_declared_bundle_resource() {
        let temp = tempfile::tempdir().expect("tempdir");
        let repo_root = temp.path();
        let metadata_path = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("runtime-metadata.json");
        let declared_binary = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("lorvex-mcp-server");
        write_runtime_metadata(
            &metadata_path,
            "app/src-tauri/resources/mcp-server/lorvex-mcp-server",
        );
        write_executable(&declared_binary);

        let resolved = find_standalone_mcp_server_binary_from(Some(repo_root), None)
            .expect("metadata lookup should not fail")
            .expect("metadata binary should resolve");

        assert_eq!(resolved, declared_binary);
    }

    #[test]
    fn packaged_metadata_resolution_rebases_repo_relative_resource_path() {
        let temp = tempfile::tempdir().expect("tempdir");
        let app_root = temp.path().join("Lorvex.app");
        let exe_path = app_root.join("Contents").join("MacOS").join("lorvex");
        let metadata_path = app_root
            .join("Contents")
            .join("Resources")
            .join("mcp-server")
            .join("runtime-metadata.json");
        let bundled_binary = app_root
            .join("Contents")
            .join("Resources")
            .join("mcp-server")
            .join("lorvex-mcp-server");
        write_runtime_metadata(
            &metadata_path,
            "app/src-tauri/resources/mcp-server/lorvex-mcp-server",
        );
        write_executable(&bundled_binary);

        let resolved = find_standalone_mcp_server_binary_from(None, Some(&exe_path))
            .expect("metadata lookup should not fail")
            .expect("metadata binary should resolve");

        assert_eq!(resolved, bundled_binary);
    }

    #[test]
    fn bad_metadata_artifact_rejects_instead_of_falling_back() {
        let temp = tempfile::tempdir().expect("tempdir");
        let repo_root = temp.path();
        let metadata_path = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("runtime-metadata.json");
        let declared_binary = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("lorvex-mcp-server");
        let fallback_binary = repo_root
            .join("mcp-server")
            .join("bin")
            .join("lorvex-mcp-server");
        write_runtime_metadata(
            &metadata_path,
            "app/src-tauri/resources/mcp-server/lorvex-mcp-server",
        );
        write_unusable_binary(&declared_binary);
        write_executable(&fallback_binary);

        let error = find_standalone_mcp_server_binary_from(Some(repo_root), None)
            .expect_err("bad metadata artifact must not fall back to heuristic probing");

        assert!(
            error.contains("missing, empty, or non-executable"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn bad_metadata_bundle_resource_directory_rejects_adjacent_binary() {
        let temp = tempfile::tempdir().expect("tempdir");
        let repo_root = temp.path();
        let metadata_path = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("runtime-metadata.json");
        let adjacent_binary = repo_root
            .join("app")
            .join("src-tauri")
            .join("resources")
            .join("mcp-server")
            .join("lorvex-mcp-server");
        write_runtime_metadata(
            &metadata_path,
            "app/src-tauri/resources/other/lorvex-mcp-server",
        );
        write_executable(&adjacent_binary);

        let error = find_standalone_mcp_server_binary_from(Some(repo_root), None)
            .expect_err("wrong metadata resource directory must not use adjacent fallback");

        assert!(
            error.contains("app/src-tauri/resources/other/lorvex-mcp-server"),
            "unexpected error: {error}"
        );
    }
}
