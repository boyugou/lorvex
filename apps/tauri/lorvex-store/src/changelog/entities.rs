//! `ai_changelog_entities` per-row entity-id registry helpers.
//!
//! Batch / bulk MCP writes touch N entities. The set is normalized
//! into the `ai_changelog_entities` child table keyed
//! `(entity_id, changelog_id)` so per-entity audit replay (Activity
//! attribution, "show me everything affecting task X") is an indexed
//! PK seek instead of a `json_each` scan over every batch row.
//! `ON DELETE CASCADE` keeps cleanup automatic when an audit row is
//! reset-deleted. The wire-form JSON array shape that consumers see
//! is reconstructed at read time by the correlated `json_group_array`
//! subquery embedded in `repositories::columns::AI_CHANGELOG`.
//!
//! ## Helpers
//!
//! - [`replace_changelog_entities`] — DELETE-then-INSERT the full set
//!   for one changelog row. `INSERT OR IGNORE` silently tolerates
//!   duplicate `(changelog_id, entity_id)` pairs in the input slice.
//! - [`load_changelog_entity_ids`] — read the registered ids back in
//!   ascending order. Matches the canonical sort the wire-form
//!   subquery emits.
//! - [`load_changelog_entity_ids_json`] — build the wire-form JSON
//!   array from the child rows. Returns `None` for an empty registry
//!   so the wire shape stays NULL-equivalent to a "no batch ids" row.
//! - [`parse_entity_ids_json`] — decode a wire-form JSON array of
//!   strings. Used by sync apply / import to rehydrate the registry
//!   from inbound envelopes.

use rusqlite::{params, Connection};

use crate::error::StoreError;

/// Replace the changelog row's full entity-id registry with the
/// provided slice. An empty slice clears the registry. `INSERT OR
/// IGNORE` silently tolerates duplicate `(changelog_id, entity_id)`
/// pairs in the input.
pub fn replace_changelog_entities(
    conn: &Connection,
    changelog_id: &str,
    entity_ids: &[String],
) -> Result<(), StoreError> {
    conn.prepare_cached("DELETE FROM ai_changelog_entities WHERE changelog_id = ?1")?
        .execute(params![changelog_id])?;
    if !entity_ids.is_empty() {
        let mut stmt = conn.prepare_cached(
            "INSERT OR IGNORE INTO ai_changelog_entities (changelog_id, entity_id) \
             VALUES (?1, ?2)",
        )?;
        for id in entity_ids {
            stmt.execute(params![changelog_id, id])?;
        }
    }
    Ok(())
}

/// Read every entity_id registered against `changelog_id`. Rows are
/// returned ASC by `entity_id`, matching the canonical sort the
/// `json_group_array(entity_id ORDER BY entity_id)` subquery uses on
/// the read path.
pub fn load_changelog_entity_ids(
    conn: &Connection,
    changelog_id: &str,
) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT entity_id FROM ai_changelog_entities \
         WHERE changelog_id = ?1 ORDER BY entity_id ASC",
    )?;
    let rows = stmt
        .query_map(params![changelog_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// Build the wire-form JSON array shape (`["task-1","task-2"]`) of
/// the changelog row's entity-id registry. Returns `None` when the
/// registry is empty so the sync envelope omits the field entirely
/// for rows that registered no entities.
pub fn load_changelog_entity_ids_json(
    conn: &Connection,
    changelog_id: &str,
) -> Result<Option<String>, StoreError> {
    let ids = load_changelog_entity_ids(conn, changelog_id)?;
    if ids.is_empty() {
        Ok(None)
    } else {
        Ok(Some(serde_json::to_string(&ids)?))
    }
}

/// Parse a wire-form JSON array of strings into a `Vec<String>`.
/// `None`, `Some("")`, and `Some(" ")` all return the empty vector.
/// Used by sync apply / import to rehydrate the registry from an
/// inbound envelope's `entity_ids` field. Invalid JSON surfaces as
/// `StoreError::Validation`.
pub fn parse_entity_ids_json(raw: Option<&str>) -> Result<Vec<String>, StoreError> {
    let Some(raw) = raw else {
        return Ok(Vec::new());
    };
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str::<Vec<String>>(raw)
        .map_err(|e| StoreError::Validation(format!("invalid ai_changelog entity_ids JSON: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::open_db_in_memory;

    fn insert_parent(conn: &Connection, id: &str) {
        conn.execute(
            "INSERT INTO ai_changelog \
             (id, timestamp, operation, entity_type, entity_id, summary, \
              initiated_by, source_device_id) \
             VALUES (?1, '2026-04-01T00:00:00Z', 'update', 'task', NULL, 'demo', 'human', 'dev')",
            params![id],
        )
        .unwrap();
    }

    #[test]
    fn replace_round_trips_through_json_helper() {
        let conn = open_db_in_memory().unwrap();
        insert_parent(&conn, "chg-1");
        replace_changelog_entities(
            &conn,
            "chg-1",
            &[
                "task-2".to_string(),
                "task-1".to_string(),
                "task-2".to_string(),
            ],
        )
        .unwrap();
        let ids = load_changelog_entity_ids(&conn, "chg-1").unwrap();
        assert_eq!(ids, vec!["task-1", "task-2"]);
        let json = load_changelog_entity_ids_json(&conn, "chg-1").unwrap();
        assert_eq!(json.as_deref(), Some(r#"["task-1","task-2"]"#));
    }

    #[test]
    fn replace_with_empty_slice_clears_registry() {
        let conn = open_db_in_memory().unwrap();
        insert_parent(&conn, "chg-1");
        replace_changelog_entities(&conn, "chg-1", &["task-1".to_string()]).unwrap();
        replace_changelog_entities(&conn, "chg-1", &[]).unwrap();
        assert!(load_changelog_entity_ids(&conn, "chg-1")
            .unwrap()
            .is_empty());
        assert_eq!(
            load_changelog_entity_ids_json(&conn, "chg-1").unwrap(),
            None
        );
    }

    #[test]
    fn cascade_delete_drops_entity_rows() {
        let conn = open_db_in_memory().unwrap();
        insert_parent(&conn, "chg-1");
        replace_changelog_entities(
            &conn,
            "chg-1",
            &["task-1".to_string(), "task-2".to_string()],
        )
        .unwrap();
        conn.execute("DELETE FROM ai_changelog WHERE id = ?1", params!["chg-1"])
            .unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM ai_changelog_entities WHERE changelog_id = ?1",
                params!["chg-1"],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 0);
    }

    #[test]
    fn attribution_lookup_uses_pk_index() {
        // Pin the indexed per-entity attribution path: filtering
        // by `entity_id = ?` must resolve through the PK
        // `(entity_id, changelog_id)`, not a scan. This is the
        // core motivation for #4613.
        let conn = open_db_in_memory().unwrap();
        let plan: Vec<String> = conn
            .prepare(
                "EXPLAIN QUERY PLAN \
                 SELECT changelog_id FROM ai_changelog_entities WHERE entity_id = ?1",
            )
            .unwrap()
            .query_map(["task-1"], |row| row.get::<_, String>(3))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        let plan_text = plan.join("\n");
        assert!(
            plan_text.to_uppercase().contains("SEARCH"),
            "per-entity attribution must use an indexed SEARCH, not a SCAN:\n{plan_text}"
        );
    }

    #[test]
    fn parse_entity_ids_json_handles_blank_and_null() {
        assert!(parse_entity_ids_json(None).unwrap().is_empty());
        assert!(parse_entity_ids_json(Some("")).unwrap().is_empty());
        assert!(parse_entity_ids_json(Some("   ")).unwrap().is_empty());
    }

    #[test]
    fn parse_entity_ids_json_returns_array() {
        let parsed = parse_entity_ids_json(Some(r#"["task-1","task-2"]"#)).unwrap();
        assert_eq!(parsed, vec!["task-1", "task-2"]);
    }

    #[test]
    fn parse_entity_ids_json_rejects_malformed() {
        let err = parse_entity_ids_json(Some("not-json")).unwrap_err();
        assert!(matches!(err, StoreError::Validation(_)));
    }
}
