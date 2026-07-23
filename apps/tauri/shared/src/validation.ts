// Mirrors lorvex-domain/src/validation/limits.rs — enforced by verify:validation-mirror-parity.
//
// Shared validation caps. Kept in lockstep with
// `lorvex-domain/src/validation/limits.rs` — the Rust module is the source
// of truth for what the DB and MCP tools accept, and these constants
// mirror those limits so every frontend `<input maxLength={…}>` and
// `<textarea maxLength={…}>` matches what the backend will actually
// store. Drift between the two produces two user-visible bugs
//: a cap that's too low silently truncates input at
// the DOM boundary (500 vs 1000 historical case on list names and
// calendar titles), and a cap that's too high lets users type past
// the backend limit and see an opaque validation error on submit.
//
// Character vs byte semantics: the backend uses
// `chars().count()`-equivalent bounds, which the browser `maxLength`
// attribute matches on modern DOM (it counts UTF-16 code units, so
// CJK within the BMP gets the same cap — surrogate pairs get half).
// This is close enough for UX purposes; the backend is still the
// authoritative check.

/** Title cap for tasks, lists, and calendar events. */
export const MAX_TITLE_LENGTH = 1_000;

/** Body / long-text cap — task bodies, memory content, etc. */
export const MAX_BODY_LENGTH = 50_000;

/** Short-text cap for tags, list descriptions, memory keys, etc. */
export const MAX_SHORT_TEXT_LENGTH = 2_000;

/** AI memory content cap, mirroring `lorvex_domain::memory::MAX_MEMORY_CONTENT_LENGTH`. */
export const MAX_MEMORY_CONTENT_LENGTH = 100_000;

/**
 * Cue cap for habits (the optional "context / trigger" string surfaced
 * next to a habit name — e.g. "After morning coffee"). The Rust
 * `habits` table accepts `TEXT`, but the UI funnels through a single
 * compact input that wants a short hint, not a paragraph; the prior
 * frontend used a magic 200 (L5/M1) which has now been
 * promoted to a named constant so the cap doesn't drift across the
 * habit form, the edit affordance, and any future cue surfaces.
 */
export const MAX_HABIT_CUE_LENGTH = 200;

/**
 * Per-tag display-name cap, mirroring `MAX_TAG_NAME_LENGTH` in
 * `lorvex-domain/src/validation/limits.rs`. Tag inputs are typically
 * comma-separated, so callers must clamp each token individually
 * rather than the whole string.
 */
export const MAX_TAG_NAME_LENGTH = 100;

/**
 * numeric / count caps that the React UI previously
 * left unbounded while the Rust validation layer rejected over-budget
 * writes at the IPC boundary. Mirrors
 * `lorvex-domain/src/validation/limits.rs` so the form-level
 * pre-checks (estimated minutes spinner, tag chip count,
 * dependency picker, reminder offset windows, mood/energy sliders,
 * priority quick-pick) line up with what the backend will actually
 * accept.
 */

/** Maximum task `estimated_minutes` (24h). */
export const MAX_ESTIMATED_MINUTES = 1_440;

/** Valid task priority range (1 = P1 / highest, 3 = P3 / lowest). */
export const PRIORITY_MIN = 1;
export const PRIORITY_MAX = 3;

/**
 * Pipe-separated display form of the priority allow-list, used in
 * validation error messages so MCP / CLI / Tauri / domain surfaces emit
 * one canonical wording (#2994 H4). Mirrors
 * `TASK_PRIORITY_ALLOWED_VALUES_DISPLAY` in
 * `lorvex-domain/src/validation/limits.rs`.
 */
export const TASK_PRIORITY_ALLOWED_VALUES_DISPLAY = '1|2|3';

/** Mood / energy_level scale bounds (daily reviews). */
export const MOOD_MIN = 1;
export const MOOD_MAX = 5;

/** Maximum number of tags attached to a single task. */
export const MAX_TASK_TAGS = 30;

/** Maximum number of `depends_on` edges per task. */
export const MAX_TASK_DEPENDENCIES = 50;

/** Maximum number of active reminders per task. */
export const MAX_REMINDERS_PER_TASK = 20;

/** Maximum reminder window in seconds (1 year). */
export const MAX_REMINDER_WINDOW_SECONDS = 365 * 24 * 3600;

/** Maximum list description length, measured in Unicode codepoints. */
export const MAX_LIST_DESCRIPTION_LENGTH = 1_000;

/** Maximum length of a preference / device_state / memory key, in Unicode codepoints. */
export const KV_KEY_MAX_CHARS = 200;

/** Maximum length of a preference / device_state JSON value, in bytes. */
export const KV_VALUE_MAX_BYTES = 50_000;

/** Maximum length of a human-seeded memory key, in Unicode codepoints. */
export const MEMORY_KEY_MAX_CHARS = 64;
