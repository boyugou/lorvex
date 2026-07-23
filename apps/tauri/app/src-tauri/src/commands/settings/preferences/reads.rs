use crate::{
    commands::OptionalExt,
    db::{get_conn, get_read_conn},
    error::{AppError, AppResult},
};
use rusqlite::params;

#[tauri::command]
pub fn get_preference(key: String) -> Result<Option<String>, String> {
    get_preference_inner(key).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn get_preference_inner(key: String) -> AppResult<Option<String>> {
    let conn = get_read_conn()?;

    // Treat invalid-UTF-8 in a preferences row as "unreadable, behave
    // as if missing" so a single bad byte (partially-flushed sync
    // apply crash, external process writing into the SQLite file,
    // disk-corruption event) cannot brick settings hydration — the
    // renderer hydrates a per-key cache on every settings open, and a
    // bubbled `AppError::Sql(InvalidColumnType{Utf8Error})` would take
    // out the whole settings panel until the user manually purged the
    // row. Log to `error_logs` so the corruption is still visible to
    // the diagnostics view + sync engineers; every other failure mode
    // (locked DB, schema drift, IO) still surfaces through
    // `AppError::Sql`.
    let result = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            params![key],
            |row| row.get::<_, String>(0),
        )
        .optional();

    match result {
        Ok(value) => Ok(value),
        Err(rusqlite::Error::InvalidColumnType(_, _, _)) => {
            // Best-effort: write a structured diagnostic so the row is
            // visible in the error-log surface. A failure to write the
            // log is itself non-fatal — we still want to return Ok(None)
            // so settings hydration completes.
            if let Ok(write_conn) = get_conn() {
                let _ = crate::commands::diagnostics::append_error_log_internal(
                    &write_conn,
                    "preferences.corrupt_row",
                    "preference value is not valid UTF-8; treating as missing",
                    Some(format!("key={key}")),
                    Some("warn".to_string()),
                );
            }
            Ok(None)
        }
        Err(e) => Err(AppError::from(e)),
    }
}

/// Batched preference fetch. Callers (notifications runtime, morning
/// briefing, weekly review) read several keys in one go via this
/// helper instead of `Promise.all([getPreference(k1), …])` — that
/// shape costs N IPC round-trips + N pool acquires + N prepared
/// statements for a table that typically has < 50 rows total. One
/// SELECT with
/// `WHERE key IN (?,?,?)` returns all of them and keeps the result
/// as a Vec<(String, String)> so the TS side can assemble its own
/// map. Missing keys are simply absent from the response — callers
/// default to None as before.
#[tauri::command]
pub fn get_preferences(keys: Vec<String>) -> Result<Vec<(String, String)>, String> {
    get_preferences_inner(keys).map_err(String::from)
}

fn get_preferences_inner(keys: Vec<String>) -> AppResult<Vec<(String, String)>> {
    if keys.is_empty() {
        return Ok(Vec::new());
    }
    let conn = get_read_conn()?;
    // Cap to a sane per-call bound. Callers asking for more than this
    // should probably call get_all_preferences instead — the
    // preferences table is small.
    const MAX_KEYS: usize = 32;
    let keys: Vec<String> = keys.into_iter().take(MAX_KEYS).collect();
    let placeholders = keys
        .iter()
        .enumerate()
        .map(|(i, _)| format!("?{}", i + 1))
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!("SELECT key, value FROM preferences WHERE key IN ({placeholders})");
    let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
    let params_refs: Vec<&dyn rusqlite::ToSql> =
        keys.iter().map(|k| k as &dyn rusqlite::ToSql).collect();
    let rows = stmt
        .query_map(rusqlite::params_from_iter(params_refs), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(AppError::from)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(AppError::from)
}

#[cfg(test)]
pub(crate) fn default_sync_backend_kind() -> &'static str {
    lorvex_domain::parsing::SyncBackendKind::platform_default().as_str()
}

#[tauri::command]
pub fn get_default_filesystem_bridge_root_path() -> Result<Option<String>, String> {
    get_default_filesystem_bridge_root_path_inner().map_err(String::from)
}

fn get_default_filesystem_bridge_root_path_inner() -> AppResult<Option<String>> {
    Ok(
        crate::platform::paths::default_filesystem_bridge_root_path()
            .map(|p| p.to_string_lossy().to_string()),
    )
}
