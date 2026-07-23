//! Canonical `ai_notes` mutation shared by MCP `set_task_ai_notes` and the
//! CLI mirror. Owns the `UPDATE tasks SET ai_notes = …, version = …, updated_at = …` SQL
//! with LWW gating; the static contract verifier keeps the same
//! `UPDATE tasks` pattern out of every other crate.
//!
//! The UPDATE is gated by `?version > version` so a stale caller
//! stamp cannot clobber a freshly-applied peer envelope. Zero rows
//! changed disambiguates between a missing row and a stale stamp by
//! a follow-up existence probe: [`StoreError::NotFound`] when the row
//! is gone, [`StoreError::StaleVersion`] when the gate rejected our
//! stamp. The surface adapter can map each to its own typed error.

use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::{params, Connection, OptionalExtension};

/// Stamp the current `ai_notes` blob onto the row, alongside a fresh
/// `version` and `updated_at`. Returns
/// [`StoreError::NotFound`] when the row does not exist and
/// [`StoreError::StaleVersion`] when the LWW gate rejects the write.
pub fn set_ai_notes_op(
    conn: &Connection,
    task_id: &TaskId,
    notes: Option<&str>,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let rows = conn.execute(
        "UPDATE tasks SET ai_notes = ?1, version = ?2, updated_at = ?3 \
         WHERE id = ?4 AND ?2 > version",
        params![notes, version, now, task_id],
    )?;
    if rows == 0 {
        let exists = conn
            .query_row(
                "SELECT 1 FROM tasks WHERE id = ?1",
                params![task_id.as_str()],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        return if exists {
            Err(StoreError::StaleVersion {
                entity: "task",
                id: task_id.as_str().to_string(),
            })
        } else {
            Err(StoreError::NotFound {
                entity: "task",
                id: task_id.as_str().to_string(),
            })
        };
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use lorvex_store::test_support::{fixtures::TaskBuilder, test_conn};

    const TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000002";

    #[test]
    fn missing_row_returns_not_found() {
        let conn = test_conn();
        let task_id = TaskId::from_trusted(TASK_ID.to_string());
        let err = set_ai_notes_op(
            &conn,
            &task_id,
            Some("note"),
            "1000000000000_0000_0000000000000000",
            "2026-04-01T09:00:00Z",
        )
        .expect_err("missing row must surface as NotFound");
        assert!(
            matches!(err, StoreError::NotFound { .. }),
            "expected NotFound, got {err:?}",
        );
    }

    #[test]
    fn existing_row_with_higher_version_returns_stale_version() {
        let conn = test_conn();
        TaskBuilder::new(TASK_ID)
            .title("t")
            .version("9999999999999_0000_ffffffffffffffff")
            .insert(&conn);
        let task_id = TaskId::from_trusted(TASK_ID.to_string());
        let err = set_ai_notes_op(
            &conn,
            &task_id,
            Some("note"),
            "0000000000001_0000_0000000000000000",
            "2026-04-01T09:00:00Z",
        )
        .expect_err("stale stamp must surface as StaleVersion");
        assert!(
            matches!(err, StoreError::StaleVersion { .. }),
            "expected StaleVersion, got {err:?}",
        );
    }
}
