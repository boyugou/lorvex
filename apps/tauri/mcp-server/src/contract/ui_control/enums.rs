//! Closed-vocabulary enums for `ControlAppUiArgs` view / theme /
//! appearance profile / language fields.
//!
//! These mirror the `AssistantUiView`, `ThemeMode`, `AppearanceProfile`,
//! and `AssistantUiLanguage` discriminated unions in
//! `shared/src/types.ts`. The `snake_case` (or explicit `rename`) serde
//! tags are the canonical wire form; an unknown variant on the MCP
//! tool boundary fails to deserialize at the JSON Schema layer
//! naturally — `rmcp` surfaces the rejection as `InvalidParams` instead
//! of slipping past the per-action allowlist gate that had
//! to do the validation by hand.
//!
//! The string-typed allowlists in `preferences::vocabulary`
//! remain the source of truth for per-action error narration (the
//! `"X must be one of …"` diagnostic surfaces the wire vocabulary so
//! the assistant can self-correct). These typed enums and the
//! string-typed allowlists are kept in lockstep by the round-trip
//! `as_wire_str` / `parse` helpers below.

use schemars::JsonSchema;
use serde::Deserialize;

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum AssistantUiView {
    Today,
    Upcoming,
    AiChangelog,
    AllTasks,
    Someday,
    Calendar,
    Eisenhower,
    Kanban,
    Dependencies,
    Memory,
    Review,
    DailyReview,
    Settings,
    List,
    Habits,
    Recurring,
}

impl AssistantUiView {
    pub(crate) const fn as_wire_str(self) -> &'static str {
        match self {
            Self::Today => "today",
            Self::Upcoming => "upcoming",
            Self::AiChangelog => "ai_changelog",
            Self::AllTasks => "all_tasks",
            Self::Someday => "someday",
            Self::Calendar => "calendar",
            Self::Eisenhower => "eisenhower",
            Self::Kanban => "kanban",
            Self::Dependencies => "dependencies",
            Self::Memory => "memory",
            Self::Review => "review",
            Self::DailyReview => "daily_review",
            Self::Settings => "settings",
            Self::List => "list",
            Self::Habits => "habits",
            Self::Recurring => "recurring",
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ThemeMode {
    Paper,
    Light,
    Dark,
    Ember,
    Midnight,
    Liquid,
    LiquidLight,
    Mica,
    MicaLight,
    Adwaita,
    AdwaitaLight,
    System,
}

impl ThemeMode {
    pub(crate) const fn as_wire_str(self) -> &'static str {
        match self {
            Self::Paper => "paper",
            Self::Light => "light",
            Self::Dark => "dark",
            Self::Ember => "ember",
            Self::Midnight => "midnight",
            Self::Liquid => "liquid",
            Self::LiquidLight => "liquid_light",
            Self::Mica => "mica",
            Self::MicaLight => "mica_light",
            Self::Adwaita => "adwaita",
            Self::AdwaitaLight => "adwaita_light",
            Self::System => "system",
        }
    }
}

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum AppearanceProfile {
    Clarity,
    Studio,
    FocusCompact,
    LiquidGlass,
}

impl AppearanceProfile {
    pub(crate) const fn as_wire_str(self) -> &'static str {
        match self {
            Self::Clarity => "clarity",
            Self::Studio => "studio",
            Self::FocusCompact => "focus_compact",
            Self::LiquidGlass => "liquid_glass",
        }
    }
}

/// `AssistantUiLanguage` — the closed locale vocabulary.
///
/// Variants are explicitly renamed (rather than relying on
/// `rename_all = "kebab-case"`) so the BCP-47 region tag (`zh-Hant`)
/// preserves its case alongside the all-lowercase ISO 639-1 codes.
#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
pub(crate) enum AssistantUiLanguage {
    #[serde(rename = "system")]
    System,
    #[serde(rename = "en")]
    En,
    #[serde(rename = "zh")]
    Zh,
    #[serde(rename = "zh-Hant")]
    ZhHant,
    #[serde(rename = "es")]
    Es,
    #[serde(rename = "fr")]
    Fr,
    #[serde(rename = "de")]
    De,
    #[serde(rename = "ja")]
    Ja,
    #[serde(rename = "ko")]
    Ko,
    #[serde(rename = "pt")]
    Pt,
    #[serde(rename = "ru")]
    Ru,
    #[serde(rename = "hi")]
    Hi,
    #[serde(rename = "ar")]
    Ar,
    #[serde(rename = "id")]
    Id,
    #[serde(rename = "it")]
    It,
    #[serde(rename = "nl")]
    Nl,
    #[serde(rename = "tr")]
    Tr,
    #[serde(rename = "pl")]
    Pl,
    #[serde(rename = "uk")]
    Uk,
    #[serde(rename = "vi")]
    Vi,
    #[serde(rename = "th")]
    Th,
    #[serde(rename = "ms")]
    Ms,
    #[serde(rename = "bn")]
    Bn,
    #[serde(rename = "te")]
    Te,
    #[serde(rename = "mr")]
    Mr,
    #[serde(rename = "ta")]
    Ta,
    #[serde(rename = "ml")]
    Ml,
    #[serde(rename = "el")]
    El,
    #[serde(rename = "ro")]
    Ro,
    #[serde(rename = "ur")]
    Ur,
    #[serde(rename = "fa")]
    Fa,
    #[serde(rename = "he")]
    He,
}

impl AssistantUiLanguage {
    pub(crate) const fn as_wire_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::En => "en",
            Self::Zh => "zh",
            Self::ZhHant => "zh-Hant",
            Self::Es => "es",
            Self::Fr => "fr",
            Self::De => "de",
            Self::Ja => "ja",
            Self::Ko => "ko",
            Self::Pt => "pt",
            Self::Ru => "ru",
            Self::Hi => "hi",
            Self::Ar => "ar",
            Self::Id => "id",
            Self::It => "it",
            Self::Nl => "nl",
            Self::Tr => "tr",
            Self::Pl => "pl",
            Self::Uk => "uk",
            Self::Vi => "vi",
            Self::Th => "th",
            Self::Ms => "ms",
            Self::Bn => "bn",
            Self::Te => "te",
            Self::Mr => "mr",
            Self::Ta => "ta",
            Self::Ml => "ml",
            Self::El => "el",
            Self::Ro => "ro",
            Self::Ur => "ur",
            Self::Fa => "fa",
            Self::He => "he",
        }
    }
}
