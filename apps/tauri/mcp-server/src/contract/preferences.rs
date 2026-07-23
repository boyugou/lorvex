use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;
use serde_json::Value;

use super::{IDEMPOTENCY_KEY_DESCRIPTION, MAX_LONG_TEXT_LENGTH};

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetPreferenceArgs {
    #[schemars(description = "Preference key")]
    pub(crate) key: String,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct SetPreferenceArgs {
    #[schemars(description = "Preference key")]
    pub(crate) key: String,
    #[schemars(
        description = "Preference value as a normal JSON value. For string preferences, pass a plain string value like \"list-id\" or \"midnight\", not a JSON-encoded string literal."
    )]
    pub(crate) value: Value,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct DeletePreferenceArgs {
    #[schemars(description = "Preference key to delete (restores computed default)")]
    pub(crate) key: String,
    // preference clear emits an undo bundle and a sync
    // tombstone — destructive enough that the assistant should be
    // able to preview the prior value (and confirm forbidden-key
    // gate passes) before committing.
    #[schemars(
        description = "Issue #3019-H5: if true, run the clear (incl. undo bundle synth + tombstone shape) and return the would-be response with `dry_run: true`, then roll back. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct CompleteSetupArgs {
    #[schemars(description = "Brief summary of what was configured during setup")]
    #[validate(string, max_length = MAX_LONG_TEXT_LENGTH)]
    pub(crate) summary: String,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
