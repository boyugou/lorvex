use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;

// ── Provider Event Links (local-only, no sync) ──────────────────────

/// Strict provider kind contract for provider-event links. Unknown
/// provider kinds fail during JSON deserialization and schema
/// validation instead of riding through as strings to the handler.
#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum KnownProviderKind {
    Eventkit,
    GoogleCalendar,
    IcalSubscription,
    Ics,
    LinuxIcs,
    Outlook,
    WindowsAppointments,
}

impl KnownProviderKind {
    #[cfg(test)]
    pub(crate) const ALL: &[KnownProviderKind] = &[
        KnownProviderKind::Eventkit,
        KnownProviderKind::GoogleCalendar,
        KnownProviderKind::IcalSubscription,
        KnownProviderKind::Ics,
        KnownProviderKind::LinuxIcs,
        KnownProviderKind::Outlook,
        KnownProviderKind::WindowsAppointments,
    ];

    pub(crate) const fn as_canonical_str(self) -> &'static str {
        match self {
            KnownProviderKind::Eventkit => lorvex_domain::PROVIDER_KIND_EVENTKIT,
            KnownProviderKind::GoogleCalendar => lorvex_domain::PROVIDER_KIND_GOOGLE_CALENDAR,
            KnownProviderKind::IcalSubscription => lorvex_domain::PROVIDER_KIND_ICAL_SUBSCRIPTION,
            KnownProviderKind::Ics => lorvex_domain::PROVIDER_KIND_ICS,
            KnownProviderKind::LinuxIcs => lorvex_domain::PROVIDER_KIND_LINUX_ICS,
            KnownProviderKind::Outlook => lorvex_domain::PROVIDER_KIND_OUTLOOK,
            KnownProviderKind::WindowsAppointments => {
                lorvex_domain::PROVIDER_KIND_WINDOWS_APPOINTMENTS
            }
        }
    }
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct LinkTaskToProviderEventArgs {
    #[schemars(description = "Task id to link")]
    #[validate(uuid)]
    pub(crate) task_id: String,
    #[schemars(description = "Provider kind. Canonical set is defined by lorvex-domain.")]
    pub(crate) provider_kind: KnownProviderKind,
    #[schemars(description = "Provider scope (e.g. calendar name or subscription id)")]
    pub(crate) provider_scope: String,
    #[schemars(description = "Provider-specific event key")]
    pub(crate) provider_event_key: String,
    // #3029-M4: optional idempotency token. Provider links are
    // local-only (no sync), so a retry inserts a duplicate row in
    // `provider_event_links` rather than being de-duped by the
    // sync apply pipeline.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate provider links; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct UnlinkTaskFromProviderEventArgs {
    #[schemars(description = "Task id")]
    #[validate(uuid)]
    pub(crate) task_id: String,
    #[schemars(
        description = "Provider kind. See `LinkTaskToProviderEventArgs.provider_kind` for the canonical set."
    )]
    pub(crate) provider_kind: KnownProviderKind,
    #[schemars(description = "Provider scope")]
    pub(crate) provider_scope: String,
    #[schemars(description = "Provider-specific event key")]
    pub(crate) provider_event_key: String,
    // #3029-M4: optional idempotency token. Cf.
    // `LinkTaskToProviderEventArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate provider unlinks; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema, ContractValidate)]
pub(crate) struct GetProviderEventLinksForTaskArgs {
    #[schemars(description = "Task id")]
    #[validate(uuid)]
    pub(crate) task_id: String,
}
