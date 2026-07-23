use super::*;

pub(super) const MISSING_TASK_UUID: &str = "01966a3f-7c8b-7d4e-8f3a-0000000000a1";
pub(super) const PRIORITY_TASK_UUID: &str = "01966a3f-7c8b-7d4e-8f3a-0000000000a2";

pub(super) fn side_effect_row_counts(server: &LorvexMcpServer) -> (i64, i64) {
    server
        .with_conn(|conn| {
            let changelog: i64 = conn
                .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
                .map_err(to_error_message)?;
            let outbox: i64 = conn
                .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
                .map_err(to_error_message)?;
            Ok((changelog, outbox))
        })
        .expect("count side-effect rows")
}
