use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ListPendingOutboxEntriesArgs {
    #[schemars(description = "Max number of entries to return (default 100, max 500)")]
    pub(crate) limit: Option<u32>,
    // #3019-M1: outbox can grow unbounded during a sync stall, so a
    // single LIMIT page leaves later entries silently inaccessible.
    // The response now includes `next_offset` for paginated walks.
    #[schemars(description = "Zero-based row offset for stable pagination. Default 0.")]
    pub(crate) offset: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum LogLevelFilter {
    Debug,
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum LogSourceFilter {
    ErrorLog,
    AiChangelog,
    SyncOutbox,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetRecentLogsArgs {
    #[schemars(description = "Max entries to return after merge/sort (default 100, max 500)")]
    pub(crate) limit: Option<u32>,
    // pagination offset over the merged stream.
    #[schemars(description = "Zero-based offset into the merged log stream. Default 0.")]
    pub(crate) offset: Option<u32>,
    #[schemars(description = "ISO timestamp - include entries newer than this time")]
    pub(crate) since: Option<String>,
    #[schemars(description = "Optional single-level convenience filter")]
    pub(crate) level: Option<LogLevelFilter>,
    #[schemars(description = "Optional level filter list")]
    pub(crate) levels: Option<Vec<LogLevelFilter>>,
    #[schemars(description = "Optional single-source convenience filter")]
    pub(crate) source: Option<LogSourceFilter>,
    #[schemars(description = "Optional source filter list")]
    pub(crate) sources: Option<Vec<LogSourceFilter>>,
    #[schemars(
        description = "Include sanitized details payload for error_log entries (default false)."
    )]
    pub(crate) include_details: Option<bool>,
    #[schemars(description = "Redact potential secrets from summaries/details (default true).")]
    pub(crate) redact: Option<bool>,
}
