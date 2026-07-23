// The per-vocabulary "display" macros (assistant_ui_views_display,
// theme_modes_display, appearance_profiles_display, and
// assistant_ui_languages_display) format an "X/Y/Z" allowlist
// string for the per-action validation diagnostic. The closed-vocabulary
// `Option<AssistantUiView>` / `Option<ThemeMode>` / etc. enums on
// `ControlAppUiArgs` now reject unknown values at the serde-deserialize
// boundary, so the string allowlists are unreachable. The remaining
// `CONTROL_APP_UI_*_FIELD_DESCRIPTION` strings still need the
// human-readable list, so each builds its allowlist inline from the
// matching `&[&str]` slice via `concat!` + per-token formatting.
//
// The kept slice constants (`ASSISTANT_UI_VIEWS`, `THEME_MODES`,
// `APPEARANCE_PROFILES`, `ASSISTANT_UI_LANGUAGES`) remain the wire-
// vocabulary source of truth — referenced by the parity tests in
// `preferences::tests` and the guidance renderer in
// `guidance_support::guide_render`.

pub(crate) const THEME_MODES: &[&str] = &[
    "paper",
    "light",
    "dark",
    "ember",
    "midnight",
    "liquid",
    "liquid_light",
    "mica",
    "mica_light",
    "adwaita",
    "adwaita_light",
    "system",
];

pub(crate) const APPEARANCE_PROFILES: &[&str] =
    &["clarity", "studio", "focus_compact", "liquid_glass"];

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) const ASSISTANT_UI_VIEWS: &[&str] = &[
    "today",
    "upcoming",
    "ai_changelog",
    "all_tasks",
    "someday",
    "calendar",
    "eisenhower",
    "kanban",
    "dependencies",
    "memory",
    "review",
    "daily_review",
    "settings",
    "list",
    "habits",
    "recurring",
];

pub(crate) const ASSISTANT_UI_LANGUAGES: &[&str] = &[
    "system", "en", "zh", "zh-Hant", "es", "fr", "de", "ja", "ko", "pt", "ru", "hi", "ar", "id",
    "it", "nl", "tr", "pl", "uk", "vi", "th", "ms", "bn", "te", "mr", "ta", "ml", "el", "ro", "ur",
    "fa", "he",
];
// MCP tool `#[schemars(description = …)]` constants for the four
// `ControlAppUiArgs` vocabulary fields. The closed-vocabulary serde
// enums on the args struct gate input at the deserialize boundary, so
// the runtime "must be one of …" validator that reuse the
// `_display!()` macros is gone — only the human-readable allowlist
// surfaced in the MCP tool schema remains. Each `concat!` body stays
// in lockstep with its sibling `&[&str]` slice above; the
// `assistant_ui_vocabulary_contracts` contract test catches a slice
// addition that forgets to extend the description string.
pub(crate) const CONTROL_APP_UI_VIEW_FIELD_DESCRIPTION: &str = concat!(
    "Required for switch_view. Supported values: ",
    "today/upcoming/ai_changelog/all_tasks/someday/calendar/eisenhower/kanban/dependencies/memory/review/daily_review/settings/list/habits/recurring",
    ". When view is list, provide list_id for an existing list.",
);
pub(crate) const CONTROL_APP_UI_THEME_FIELD_DESCRIPTION: &str = concat!(
    "Required for set_theme. Supported values: ",
    "paper/light/dark/ember/midnight/liquid/liquid_light/mica/mica_light/adwaita/adwaita_light/system",
    ".",
);
pub(crate) const CONTROL_APP_UI_APPEARANCE_PROFILE_FIELD_DESCRIPTION: &str = concat!(
    "Required for set_appearance_profile. Supported values: ",
    "clarity/studio/focus_compact/liquid_glass",
    ".",
);
pub(crate) const CONTROL_APP_UI_LANGUAGE_FIELD_DESCRIPTION: &str = concat!(
    "Required for set_language. Supported values: ",
    "system/en/zh/zh-Hant/es/fr/de/ja/ko/pt/ru/hi/ar/id/it/nl/tr/pl/uk/vi/th/ms/bn/te/mr/ta/ml/el/ro/ur/fa/he",
    ".",
);
