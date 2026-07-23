use std::path::PathBuf;

/// Resolve the database file path. Priority:
/// 1. `DB_PATH` environment variable (for development)
/// 2. Platform data directory via `dirs::data_dir()` (default)
pub fn resolve_db_path() -> PathBuf {
    lorvex_runtime::resolve_db_path()
}
