use crate::error::StoreError;
use crate::load_setup_status;
use rusqlite::{params, Connection, OptionalExtension};

pub fn validate_task_list_exists(
    conn: &Connection,
    list_id: &lorvex_domain::ListId,
) -> Result<(), StoreError> {
    if list_id.as_str().is_empty() {
        return Err(StoreError::Validation(
            "list_id must not be empty".to_string(),
        ));
    }

    let exists = conn
        .query_row(
            "SELECT 1 FROM lists WHERE id = ?1",
            params![list_id],
            |_row| Ok(()),
        )
        .optional()?
        .is_some();

    if !exists {
        return Err(StoreError::Validation(format!(
            "list '{list_id}' does not exist"
        )));
    }

    Ok(())
}

pub fn resolve_required_task_list_id(
    conn: &Connection,
    explicit_list_id: Option<&str>,
) -> Result<String, StoreError> {
    if let Some(list_id) = explicit_list_id {
        let typed = lorvex_domain::ListId::from_trusted(list_id.to_string());
        validate_task_list_exists(conn, &typed)?;
        return Ok(list_id.to_string());
    }

    let setup_status = load_setup_status(conn)?;
    let Some(default_list_id) = setup_status.default_list_id else {
        return Err(StoreError::Validation(
            "Task creation requires a real list. Provide list_id or configure default_list_id first."
                .to_string(),
        ));
    };

    if !setup_status.default_list_ready {
        return Err(StoreError::Validation(
            "default_list_id does not reference an existing list.".to_string(),
        ));
    }

    Ok(default_list_id)
}

#[cfg(test)]
mod tests;
