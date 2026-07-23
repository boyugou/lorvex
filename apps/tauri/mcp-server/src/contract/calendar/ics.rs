use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ExportCalendarIcsArgs {
    #[schemars(description = "Inclusive lower bound date (YYYY-MM-DD)")]
    pub(crate) from: String,
    #[schemars(description = "Inclusive upper bound date (YYYY-MM-DD)")]
    pub(crate) to: String,
}
