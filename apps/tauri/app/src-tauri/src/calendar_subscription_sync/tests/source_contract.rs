#[test]
fn calendar_subscription_ipc_results_are_typed_structs_not_free_form_json() {
    let module_source = std::fs::read_to_string("src/calendar_subscription_sync/mod.rs")
        .expect("read calendar subscription module source");
    let workflow_mutation_source =
        std::fs::read_to_string("../../lorvex-workflow/src/calendar_subscription/mutations.rs")
            .expect("read workflow calendar subscription mutation source");
    // `sync.rs` was split into a `sync/` module; concatenate its files so the
    // typed-result structs are found wherever they now live within it.
    let workflow_sync_source = {
        let dir = std::path::Path::new("../../lorvex-workflow/src/calendar_subscription/sync");
        let mut combined = String::new();
        for entry in std::fs::read_dir(dir).expect("read workflow calendar subscription sync dir") {
            let path = entry.expect("sync dir entry").path();
            if path.extension().is_some_and(|ext| ext == "rs") {
                combined.push_str(
                    &std::fs::read_to_string(&path).expect("read workflow sync source file"),
                );
                combined.push('\n');
            }
        }
        combined
    };
    let native_source = std::fs::read_to_string("src/calendar_subscription_sync/native.rs")
        .expect("read native calendar bridge source");

    for forbidden in [
        "list_calendar_subscriptions() -> Result<serde_json::Value",
        "add_calendar_subscription(\n    name: String,\n    url: String,\n    color: Option<String>,\n) -> Result<serde_json::Value",
        "remove_calendar_subscription(id: String) -> Result<serde_json::Value",
        "toggle_calendar_subscription(\n    id: String,\n    enabled: bool,\n) -> Result<serde_json::Value",
        "update_calendar_subscription_color(\n    id: String,\n    color: Option<String>,\n) -> Result<serde_json::Value",
        "clear_native_calendar_events(source: String) -> Result<serde_json::Value",
    ] {
        assert!(
            !module_source.contains(forbidden) && !native_source.contains(forbidden),
            "Tauri command still returns free-form JSON: {forbidden}"
        );
    }

    for forbidden in [
        "AppResult<serde_json::Value>",
        "Ok(serde_json::json!({",
        "Ok(serde_json::Value::Array(rows))",
    ] {
        assert!(
            !module_source.contains(forbidden) && !native_source.contains(forbidden),
            "calendar/native helper still builds free-form JSON: {forbidden}"
        );
    }

    for required in [
        "pub struct CalendarSubscription",
        "pub enum CalendarSubscriptionSyncHealth",
        "pub struct RemoveCalendarSubscriptionResult",
        "pub struct ToggleCalendarSubscriptionResult",
        "pub struct UpdateCalendarSubscriptionColorResult",
        "pub struct ClearNativeCalendarEventsResult",
        "pub struct SubscriptionSyncResult",
    ] {
        assert!(
            module_source.contains(required)
                || workflow_mutation_source.contains(required)
                || workflow_sync_source.contains(required)
                || native_source.contains(required),
            "missing typed IPC result: {required}"
        );
    }
}
