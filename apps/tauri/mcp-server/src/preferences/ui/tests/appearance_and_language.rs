use super::*;
use crate::contract::{AppearanceProfile, AssistantUiLanguage, ThemeMode};

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_accepts_shared_theme_modes() {
    let conn = open_temp_db();

    for (theme, wire) in [
        (ThemeMode::Midnight, "midnight"),
        (ThemeMode::Ember, "ember"),
    ] {
        let response = control_app_ui(
            &conn,
            ControlAppUiArgs {
                action: UiAction::SetTheme,
                task_id: None,
                view: None,
                list_id: None,
                theme: Some(theme),
                appearance_profile: None,
                language: None,
                allow_replace_pending: None,
                note: Some("test".to_string()),
            },
        )
        .unwrap_or_else(|error| panic!("theme {wire} should be accepted, got: {error}"));

        let payload: Value = serde_json::from_str(&response).expect("parse response");
        assert_eq!(
            payload.get("action").and_then(Value::as_str),
            Some("set_theme")
        );
        assert_eq!(
            payload
                .get("command")
                .and_then(|command| command.get("value"))
                .and_then(|value| value.get("theme"))
                .and_then(Value::as_str),
            Some(wire),
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_accepts_shared_appearance_profiles() {
    let conn = open_temp_db();

    for (profile, wire) in [
        (AppearanceProfile::Clarity, "clarity"),
        (AppearanceProfile::LiquidGlass, "liquid_glass"),
    ] {
        let response = control_app_ui(
            &conn,
            ControlAppUiArgs {
                action: UiAction::SetAppearanceProfile,
                task_id: None,
                view: None,
                list_id: None,
                theme: None,
                appearance_profile: Some(profile),
                language: None,
                allow_replace_pending: None,
                note: Some("test".to_string()),
            },
        )
        .unwrap_or_else(|error| {
            panic!("appearance_profile {wire} should be accepted, got: {error}")
        });

        let payload: Value = serde_json::from_str(&response).expect("parse response");
        assert_eq!(
            payload.get("action").and_then(Value::as_str),
            Some("set_appearance_profile")
        );
        assert_eq!(
            payload
                .get("command")
                .and_then(|command| command.get("value"))
                .and_then(|value| value.get("appearance_profile"))
                .and_then(Value::as_str),
            Some(wire),
        );
    }
}

/// The closed `AssistantUiLanguage` enum on `ControlAppUiArgs.language`
/// rejects unknown variants at the serde-deserialize layer — exercising
/// that gate is now a JSON parse test, not a runtime validation test.
/// The `control_app_ui` body never receives the unknown value.
#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_args_reject_unknown_language_at_deserialize() {
    let err = serde_json::from_value::<ControlAppUiArgs>(serde_json::json!({
        "action": "set_language",
        "language": "pirate",
        "note": "test",
    }))
    .expect_err("unknown language must be rejected at the deserialize boundary");
    let message = err.to_string();
    assert!(
        message.contains("pirate") || message.contains("unknown variant"),
        "deserialize error should narrate the rejected variant, got: {message}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn control_app_ui_accepts_valid_language_values() {
    let conn = open_temp_db();

    for (language, wire) in [
        (AssistantUiLanguage::System, "system"),
        (AssistantUiLanguage::Zh, "zh"),
    ] {
        let response = control_app_ui(
            &conn,
            ControlAppUiArgs {
                action: UiAction::SetLanguage,
                task_id: None,
                view: None,
                list_id: None,
                theme: None,
                appearance_profile: None,
                language: Some(language),
                allow_replace_pending: None,
                note: Some("test".to_string()),
            },
        )
        .unwrap_or_else(|error| panic!("language {wire} should be accepted, got: {error}"));

        let payload: Value = serde_json::from_str(&response).expect("parse response");
        assert_eq!(
            payload.get("action").and_then(Value::as_str),
            Some("set_language")
        );
        assert_eq!(
            payload
                .get("command")
                .and_then(|command| command.get("value"))
                .and_then(|value| value.get("language"))
                .and_then(Value::as_str),
            Some(wire),
        );
    }
}
