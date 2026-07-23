//! Preferences domain modules — split from the old `server_preferences` /
//! `server_preferences_ui` tree.

pub(crate) mod router;
mod storage;
#[cfg(test)]
mod tests;
pub(crate) mod ui;
mod vocabulary;

#[cfg(test)]
pub(crate) use storage::load_preference_row;
pub(crate) use storage::{
    delete_preference, get_all_preferences, get_preference, parse_preference_row_value,
    set_preference,
};
pub(crate) use vocabulary::{
    APPEARANCE_PROFILES, ASSISTANT_UI_LANGUAGES,
    CONTROL_APP_UI_APPEARANCE_PROFILE_FIELD_DESCRIPTION, CONTROL_APP_UI_LANGUAGE_FIELD_DESCRIPTION,
    CONTROL_APP_UI_THEME_FIELD_DESCRIPTION, CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION, THEME_MODES,
};
// `ASSISTANT_UI_VIEWS` is reached only by the parity tests in
// `preferences::tests`; cfg-gated so the production binary
// doesn't carry the slice constant in its dead-code surface.
#[cfg(test)]
pub(crate) use vocabulary::ASSISTANT_UI_VIEWS;
