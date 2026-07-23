//! Shared test utilities for the Tauri backend crate.
//!
//! Provides a single canonical `test_conn()` that replaces the copy-pasted
//! per-module versions.  Uses `lorvex_store::open_db_in_memory()` so the
//! connection gets PRAGMAs, all migrations, and repair steps — matching
//! what the MCP server already does.
//!
//! On happy path this is byte-identical to the old version (a single
//! `open_db_in_memory()` call). On failure it routes through
//! [`lorvex_store::test_support::diag::open_test_db_with_diag`] so CI
//! logs show the temp-dir path, free space, writability probe, and
//! a pointer to `docs/execution/TEST_FLAKINESS.md`. See issue #2544.

#[cfg(test)]
pub(crate) fn test_conn() -> rusqlite::Connection {
    crate::hlc::ensure_hlc_for_test();
    match lorvex_store::open_db_in_memory() {
        Ok(conn) => conn,
        Err(_) => {
            // Re-invoke through the diagnostic wrapper so the panic
            // message carries the full context (path, free bytes,
            // writability, playbook pointer). The wrapper produces
            // the same failure class but its Display impl is rich.
            match lorvex_store::test_support::diag::open_test_db_with_diag() {
                Ok((conn, _ctx)) => conn,
                Err(diag_err) => panic!("{diag_err}"),
            }
        }
    }
}

#[cfg(test)]
pub(crate) fn fixture_uuid(label: &str) -> String {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for byte in label.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!(
        "01966a3f-7c8b-7d4e-8f3a-{:012x}",
        hash & 0x0000_ffff_ffff_ffff
    )
}

#[cfg(test)]
mod fixture_uuid_tests {
    use lorvex_domain::naming::EntityKind;

    use super::fixture_uuid;

    #[test]
    fn fixture_uuid_outputs_sync_safe_entity_and_edge_ids() {
        let task_id = fixture_uuid("task");
        let tag_id = fixture_uuid("tag");
        let event_id = fixture_uuid("calendar-event");
        let reminder_id = fixture_uuid("reminder");
        let checklist_item_id = fixture_uuid("checklist-item");
        let dependency_id = fixture_uuid("dependency");

        for (kind, id) in [
            (EntityKind::Task, task_id.as_str()),
            (EntityKind::Tag, tag_id.as_str()),
            (EntityKind::CalendarEvent, event_id.as_str()),
            (EntityKind::TaskReminder, reminder_id.as_str()),
            (EntityKind::TaskChecklistItem, checklist_item_id.as_str()),
        ] {
            lorvex_domain::validate_sync_entity_id_for_kind(kind, id)
                .expect("fixture id should satisfy sync envelope validation");
        }

        for (kind, id) in [
            (EntityKind::TaskTag, format!("{task_id}:{tag_id}")),
            (
                EntityKind::TaskDependency,
                format!("{task_id}:{dependency_id}"),
            ),
            (
                EntityKind::TaskCalendarEventLink,
                format!("{task_id}:{event_id}"),
            ),
        ] {
            lorvex_domain::validate_sync_entity_id_for_kind(kind, &id)
                .expect("fixture edge id should satisfy sync envelope validation");
        }
    }
}
