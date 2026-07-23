mod control;
mod parsing;
#[cfg(test)]
mod tests;

pub(crate) const ASSISTANT_UI_COMMAND_KEY: &str =
    lorvex_domain::preference_keys::DEV_ASSISTANT_UI_COMMAND;
pub(crate) const ASSISTANT_UI_HANDLED_ID_KEY: &str =
    lorvex_domain::preference_keys::DEV_ASSISTANT_UI_COMMAND_HANDLED_ID;

pub(crate) use control::control_app_ui;
pub(crate) use parsing::{parse_ui_command_metadata, ui_action_to_str};
