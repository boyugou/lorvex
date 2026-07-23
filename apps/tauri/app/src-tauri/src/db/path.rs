use std::path::PathBuf;

pub fn db_path() -> PathBuf {
    lorvex_runtime::resolve_db_path()
}

/// Delegate to the shared lorvex-runtime helper so this crate,
/// lorvex-store, and mcp-server all serialize DB_PATH env mutation
/// on the same process-wide mutex. Per-crate private locks would
/// only be safe-by-accident under cargo per-binary test isolation.
#[cfg(test)]
pub(crate) fn with_db_path_env_for_test(value: &str, assertion: impl FnOnce()) {
    lorvex_runtime::with_db_path_env_for_test(Some(value), assertion);
}
