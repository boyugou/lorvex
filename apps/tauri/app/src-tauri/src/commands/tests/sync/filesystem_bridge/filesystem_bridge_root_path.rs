use super::*;

#[test]
fn resolve_filesystem_bridge_root_path_rejects_empty() {
    let result = resolve_filesystem_bridge_root_path("   ");
    assert!(result.is_err());
}

#[test]
fn resolve_filesystem_bridge_root_path_expands_home_prefix() {
    let Some(home) = dirs::home_dir() else {
        return;
    };
    let resolved = resolve_filesystem_bridge_root_path("~/LorvexSync").expect("resolve ~/ path");
    assert_eq!(resolved, home.join("LorvexSync"));
}

#[test]
fn resolve_filesystem_bridge_root_path_rejects_relative_path() {
    // Mirrors data_snapshot::import — a malformed IPC string that
    // slips a relative path through must not be treated as if it were
    // anchored at an absolute location. The user picks the bridge
    // root via the OS folder dialog, so the only legitimate inputs
    // are absolute or `~`-prefixed.
    let err = resolve_filesystem_bridge_root_path("relative/sync/folder")
        .expect_err("relative paths must be rejected");
    let message = format!("{err}");
    assert!(
        message.contains("absolute"),
        "error should mention absolute requirement, got: {message}"
    );
}

#[test]
fn resolve_filesystem_bridge_root_path_rejects_parent_dir_segment() {
    // `..` components must still be rejected, including after `~/`
    // expansion. The component-aware check means a folder name that
    // merely contains the substring `..` (e.g. `My..Project`) keeps
    // working; only an actual parent-walk segment fails.
    let err = resolve_filesystem_bridge_root_path("/tmp/lorvex/../etc")
        .expect_err("`..` segments must be rejected");
    let message = format!("{err}");
    assert!(
        message.contains(".."),
        "error should mention '..' rule, got: {message}"
    );
}
