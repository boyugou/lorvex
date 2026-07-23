use crate::error::StoreError;
use rusqlite::{params, Connection, OptionalExtension};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct SetupStatus {
    pub list_count: i64,
    pub default_list_id: Option<String>,
    pub lists_ready: bool,
    pub default_list_ready: bool,
    pub working_hours_ready: bool,
    pub normal_task_creation_ready: bool,
    pub prerequisites_ready: bool,
    pub explicit_setup_completed: bool,
    pub setup_completed: bool,
}

fn read_preference_string(conn: &Connection, key: &str) -> Result<Option<String>, StoreError> {
    Ok(conn
        .prepare_cached("SELECT value FROM preferences WHERE key = ?1")?
        .query_row(params![key], |row| row.get::<_, String>(0))
        .optional()?)
}

fn read_bool_preference(conn: &Connection, key: &str) -> Result<Option<bool>, StoreError> {
    read_preference_string(conn, key)?.map_or(Ok(None), |raw| {
        lorvex_domain::parse_json_bool_preference(Some(&raw))
            .map(Some)
            .ok_or_else(|| {
                StoreError::Validation(format!("{key} preference must be a JSON boolean"))
            })
    })
}

fn read_string_preference(conn: &Connection, key: &str) -> Result<Option<String>, StoreError> {
    read_preference_string(conn, key)?.map_or(Ok(None), |raw| {
        lorvex_domain::parse_json_string_preference(Some(&raw))
            .map(Some)
            .ok_or_else(|| {
                StoreError::Validation(format!("{key} preference must be a JSON string"))
            })
    })
}

pub fn load_setup_status(conn: &Connection) -> Result<SetupStatus, StoreError> {
    let list_count: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM lists")?
        .query_row([], |row| row.get(0))?;
    let default_list_id =
        read_string_preference(conn, lorvex_domain::preference_keys::PREF_DEFAULT_LIST_ID)?;
    let default_list_ready = if let Some(ref list_id) = default_list_id {
        conn.prepare_cached("SELECT 1 FROM lists WHERE id = ?1")?
            .query_row(params![list_id], |_row| Ok(()))
            .optional()?
            .is_some()
    } else {
        false
    };
    let working_hours_ready = conn
        .prepare_cached("SELECT 1 FROM preferences WHERE key = ?1")?
        .query_row(
            params![lorvex_domain::preference_keys::PREF_WORKING_HOURS],
            |_row| Ok(()),
        )
        .optional()?
        .is_some();
    let explicit_setup_completed =
        read_bool_preference(conn, lorvex_domain::preference_keys::PREF_SETUP_COMPLETED)?
            .unwrap_or(false);
    let readiness = lorvex_domain::derive_setup_readiness(&lorvex_domain::SetupReadinessInput {
        explicit_setup_completed,
        list_count,
        default_list_ready,
        working_hours_ready,
    });

    Ok(SetupStatus {
        list_count,
        default_list_id,
        lists_ready: readiness.lists_ready,
        default_list_ready: readiness.default_list_ready,
        working_hours_ready: readiness.working_hours_ready,
        normal_task_creation_ready: readiness.normal_task_creation_ready,
        prerequisites_ready: readiness.prerequisites_ready,
        explicit_setup_completed: readiness.explicit_setup_completed,
        setup_completed: readiness.setup_completed,
    })
}

#[cfg(test)]
mod tests;
