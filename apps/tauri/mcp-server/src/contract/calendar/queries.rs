use crate::contract::{default_calendar_events_limit, default_include_provider};
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetCalendarEventArgs {
    #[schemars(description = "Calendar event id")]
    pub(crate) id: String,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetCalendarEventsArgs {
    #[schemars(description = "Inclusive lower bound date (YYYY-MM-DD)")]
    pub(crate) from: String,
    #[schemars(description = "Inclusive upper bound date (YYYY-MM-DD)")]
    pub(crate) to: String,
    #[serde(default = "default_calendar_events_limit")]
    #[schemars(description = "Maximum number of events to return. Default 200 (hard cap 1000).")]
    pub(crate) limit: u32,
    // pagination offset over the canonical events
    // result set. Provider events still come back as a single slice
    // (the timeline merge is bounded by `limit`) so this offset only
    // applies cleanly when `include_provider=false`. Documented in
    // the schema description below.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination over the canonical events. Default 0. Note: only fully meaningful when include_provider=false.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
    #[serde(default = "default_include_provider")]
    #[schemars(
        description = "Include provider events (EventKit, .ics subscriptions) in the result. Defaults to true so planning and conflict avoidance see all events. Set to false for canonical-only queries."
    )]
    pub(crate) include_provider: bool,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct SearchCalendarEventsArgs {
    #[schemars(description = "Title substring to search for (case-insensitive)")]
    pub(crate) query: String,
    #[schemars(description = "Optional lower bound date (YYYY-MM-DD)")]
    pub(crate) from: Option<String>,
    #[schemars(description = "Optional upper bound date (YYYY-MM-DD)")]
    pub(crate) to: Option<String>,
    #[serde(default = "default_calendar_events_limit")]
    #[schemars(description = "Maximum number of events to return. Default 200 (hard cap 1000).")]
    pub(crate) limit: u32,
    // pagination offset.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}
