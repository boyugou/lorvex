use super::*;
use crate::test_support::test_conn;

#[test]
fn append_window_restore_log_with_conn_persists_structured_diagnostic() {
    let conn = test_conn();

    append_window_restore_log_with_conn(
        &conn,
        "Warning",
        "Window restore test diagnostic token=message-secret",
        Some("stage=test token=details-secret".to_string()),
    )
    .expect("append window restore diagnostic");

    let row: (String, String, String, Option<String>) = conn
        .query_row(
            "SELECT source, level, message, details FROM error_logs",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read diagnostic row");

    assert_eq!(row.0, WINDOW_RESTORE_LOG_SOURCE);
    assert_eq!(row.1, "warn");
    assert_eq!(row.2, "Window restore test diagnostic token=[REDACTED]");
    assert_eq!(row.3.as_deref(), Some("stage=test token=[REDACTED]"));
}
