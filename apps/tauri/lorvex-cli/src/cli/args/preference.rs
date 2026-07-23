//! Preference argument structs.

use clap::{Args, Subcommand};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum PreferenceCmd {
    /// List all preferences.
    List,
    /// Read one preference.
    Get(PreferenceKeyArgs),
    /// Set a preference to a JSON value.
    Set(PreferenceSetArgs),
    /// Delete a preference, restoring computed default behavior.
    Delete(PreferenceKeyArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct PreferenceKeyArgs {
    pub(in crate::cli) key: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct PreferenceSetArgs {
    pub(in crate::cli) key: String,
    /// JSON value. Strings must be quoted for JSON, e.g. '"list-id"'.
    pub(in crate::cli) value_json: String,
}
