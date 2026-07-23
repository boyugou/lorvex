use super::super::args::{PreferenceCmd, PreferenceKeyArgs, PreferenceSetArgs};
use super::super::command::{Command, OutputFormat, PreferencesCommand};

pub(in crate::cli) fn translate_preference(cmd: PreferenceCmd) -> Command {
    Command::Preferences(match cmd {
        PreferenceCmd::List => PreferencesCommand::List {
            format: OutputFormat::default(),
        },
        PreferenceCmd::Get(PreferenceKeyArgs { key }) => PreferencesCommand::Get {
            key,
            format: OutputFormat::default(),
        },
        PreferenceCmd::Set(PreferenceSetArgs { key, value_json }) => PreferencesCommand::Set {
            key,
            value_json,
            format: OutputFormat::default(),
        },
        PreferenceCmd::Delete(PreferenceKeyArgs { key }) => PreferencesCommand::Delete {
            key,
            format: OutputFormat::default(),
        },
    })
}
