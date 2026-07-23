use super::*;
use serde_json::Value;

#[test]
#[serial_test::serial(hlc)]
fn get_setup_status_rejects_malformed_setup_completed_preference() {
    let server = make_server();
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z')",
                (
                    lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
                    "{not-valid-json",
                ),
            )
            .map_err(to_error_message)?;

            let error = crate::system::setup::get_setup_status(conn)
                .expect_err("malformed setup_completed should fail")
                .to_string();
            assert!(
                error.contains("setup_completed"),
                "unexpected error: {error}"
            );
            Ok(())
        })
        .expect("test");
}

#[test]
#[serial_test::serial(hlc)]
fn get_setup_status_rejects_malformed_existing_preference_value() {
    let server = make_server();
    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z')",
                ("workspace_state", "{not-valid-json"),
            )
            .map_err(to_error_message)?;

            let error = crate::system::setup::get_setup_status(conn)
                .expect_err("malformed existing preference should fail")
                .to_string();
            assert!(
                error.contains("workspace_state"),
                "unexpected error: {error}"
            );
            Ok(())
        })
        .expect("test");
}

#[test]
#[serial_test::serial(hlc)]
fn get_setup_status_requires_working_hours_for_derived_completion() {
    let server = make_server();
    server
        .with_conn(|conn| {
            // The schema seeds an 'inbox' list + default_list_id preference,
            // so no extra seeding is needed for normal_task_creation_ready.

            let payload = crate::system::setup::get_setup_status(conn).map_err(to_error_message)?;
            let value: Value = serde_json::from_str(&payload).map_err(to_error_message)?;
            assert_eq!(value["setup_completed"], false);
            assert_eq!(value["setup_state"]["normal_task_creation_ready"], true);
            assert_eq!(value["setup_state"]["working_hours_ready"], false);
            assert_eq!(value["setup_state"]["prerequisites_ready"], false);
            assert_eq!(value["setup_state"]["explicit_setup_completed"], false);

            conn.execute(
                "INSERT INTO preferences (key, value, version, updated_at)
                 VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-29T00:00:00Z')",
                (
                    lorvex_domain::preference_keys::PREF_WORKING_HOURS,
                    "{\"start\":\"09:00\",\"end\":\"17:00\"}",
                ),
            )
            .map_err(to_error_message)?;

            let payload = crate::system::setup::get_setup_status(conn).map_err(to_error_message)?;
            let value: Value = serde_json::from_str(&payload).map_err(to_error_message)?;
            assert_eq!(value["setup_completed"], true);
            assert_eq!(value["setup_state"]["prerequisites_ready"], true);
            Ok(())
        })
        .expect("test");
}
