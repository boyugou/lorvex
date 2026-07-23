use super::*;

#[test]
#[serial_test::serial(hlc)]
fn rust_assistant_ui_actions_match_shared_contract() {
    let rust_actions = [
        UiAction::EnterFocusMode,
        UiAction::ExitFocusMode,
        UiAction::FocusTask,
        UiAction::OpenTask,
        UiAction::SwitchView,
        UiAction::SetTheme,
        UiAction::SetAppearanceProfile,
        UiAction::SetLanguage,
    ]
    .into_iter()
    .map(ui_action_to_str)
    .map(str::to_string)
    .collect::<Vec<_>>();
    assert_eq!(rust_actions, shared_assistant_ui_actions());
}

#[test]
#[serial_test::serial(hlc)]
fn assistant_ui_device_state_keys_reuse_domain_registry() {
    assert_eq!(
        ASSISTANT_UI_COMMAND_KEY,
        lorvex_domain::preference_keys::DEV_ASSISTANT_UI_COMMAND,
    );
    assert_eq!(
        ASSISTANT_UI_HANDLED_ID_KEY,
        lorvex_domain::preference_keys::DEV_ASSISTANT_UI_COMMAND_HANDLED_ID,
    );
}
