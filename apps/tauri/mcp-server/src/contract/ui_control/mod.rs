use crate::preferences::{
    CONTROL_APP_UI_APPEARANCE_PROFILE_FIELD_DESCRIPTION, CONTROL_APP_UI_LANGUAGE_FIELD_DESCRIPTION,
    CONTROL_APP_UI_THEME_FIELD_DESCRIPTION, CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION,
};
use schemars::JsonSchema;

mod enums;

pub(crate) use enums::{AppearanceProfile, AssistantUiLanguage, AssistantUiView, ThemeMode};

#[derive(Debug, Clone, Copy, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum UiAction {
    EnterFocusMode,
    ExitFocusMode,
    FocusTask,
    OpenTask,
    SwitchView,
    SetTheme,
    SetAppearanceProfile,
    SetLanguage,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ControlAppUiArgs {
    #[schemars(description = "UI action to execute")]
    pub(crate) action: UiAction,
    #[schemars(
        description = "Required for focus_task/open_task. focus_task requires an open task; open_task requires an existing task. Optional for enter_focus_mode to target a specific open task."
    )]
    pub(crate) task_id: Option<String>,
    #[schemars(description = CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION)]
    pub(crate) view: Option<AssistantUiView>,
    #[schemars(description = "Required when view is list")]
    pub(crate) list_id: Option<String>,
    #[schemars(description = CONTROL_APP_UI_THEME_FIELD_DESCRIPTION)]
    pub(crate) theme: Option<ThemeMode>,
    #[schemars(description = CONTROL_APP_UI_APPEARANCE_PROFILE_FIELD_DESCRIPTION)]
    pub(crate) appearance_profile: Option<AppearanceProfile>,
    #[schemars(description = CONTROL_APP_UI_LANGUAGE_FIELD_DESCRIPTION)]
    pub(crate) language: Option<AssistantUiLanguage>,
    #[schemars(description = "When false, fail if pending assistant_ui_command exists.")]
    pub(crate) allow_replace_pending: Option<bool>,
    #[schemars(description = "Optional note for audit trail")]
    pub(crate) note: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct UiCommandMetadata {
    pub(crate) command_id: String,
    pub(crate) action: String,
    pub(crate) requested_at: Option<String>,
    pub(crate) requested_by: Option<String>,
    pub(crate) task_id: Option<String>,
    pub(crate) view: Option<String>,
    pub(crate) list_id: Option<String>,
    pub(crate) theme: Option<String>,
    pub(crate) appearance_profile: Option<String>,
    pub(crate) language: Option<String>,
    pub(crate) note: Option<String>,
}

#[cfg(test)]
mod tests;
