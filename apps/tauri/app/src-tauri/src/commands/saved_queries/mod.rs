//! Compatibility IPC for the removed `saved_queries` feature.
//!
//! The shared schema no longer contains the `saved_queries` table. Keep the
//! command names stable so older renderer code degrades safely: reads return no
//! rows, deletes are idempotent, and saves return an explicit error instead of
//! touching a missing table.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedQuery {
    pub id: String,
    pub view_type: String,
    pub name: String,
    pub filter_json: String,
    pub created_at: String,
    pub updated_at: String,
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn save_query(
    _view_type: String,
    _name: String,
    _filter_json: String,
) -> Result<SavedQuery, String> {
    Err("saved queries are no longer persisted by this schema".to_string())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn list_saved_queries(_view_type: String) -> Result<Vec<SavedQuery>, String> {
    Ok(Vec::new())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn load_saved_query(_id: String) -> Result<Option<SavedQuery>, String> {
    Ok(None)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_saved_query(_id: String) -> Result<(), String> {
    Ok(())
}
