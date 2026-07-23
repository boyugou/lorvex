use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetAiChangelogArgs {
    #[schemars(description = "Max entries to return (default 50, max 200)")]
    pub(crate) limit: Option<u32>,
    // pagination offset for the changelog stream.
    #[schemars(description = "Zero-based offset for stable pagination. Default 0.")]
    pub(crate) offset: Option<u32>,
    #[schemars(description = "Filter by entity type")]
    pub(crate) entity_type: Option<String>,
    #[schemars(description = "Filter by operation")]
    pub(crate) operation: Option<String>,
    #[schemars(description = "Filter by a specific entity id")]
    pub(crate) entity_id: Option<String>,
    #[schemars(description = "ISO timestamp, only entries after this time")]
    pub(crate) since: Option<String>,
}
