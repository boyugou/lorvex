//! Validation limit constants.
//!
//! All caller surfaces (MCP server, Tauri commands, sync apply, frontend
//! pre-checks via `shared/src/validation.ts`) reference these names so any
//! change to a bound is a single-file edit.

/// Maximum title length for tasks and lists, measured in Unicode
/// codepoints. Every write surface (MCP server, Tauri commands, sync
/// apply) counts codepoints so a 1000-character title with multi-byte
/// glyphs validates uniformly.
pub const MAX_TITLE_LENGTH: usize = 1_000;

/// Maximum body length for tasks / list descriptions / calendar event
/// descriptions, measured in Unicode codepoints. See
/// [`MAX_TITLE_LENGTH`] for the unit choice.
///
/// Capped at 50 KB — large enough for realistic bodies, small enough
/// that Milkdown's ProseMirror parse stays well under ~80 KB where
/// decoration-set perf cliffs start. Every write surface (MCP server,
/// Tauri app, sync apply) reads this constant directly so the bound
/// stays single-sourced.
pub const MAX_BODY_LENGTH: usize = 50_000;

/// Valid priority range (1-3, importance-first).
pub const PRIORITY_MIN: i64 = 1;
pub const PRIORITY_MAX: i64 = 3;

/// Pipe-separated display form of the priority allow-list, used in
/// validation error messages so MCP / CLI / Tauri / domain surfaces
/// emit one canonical wording (#2994 H4).
pub const TASK_PRIORITY_ALLOWED_VALUES_DISPLAY: &str = "1|2|3";

/// Maximum estimated_minutes (24 hours).
pub const MAX_ESTIMATED_MINUTES: i64 = 1440;

/// Maximum short-text field length (location, person_name, etc.).
pub const MAX_SHORT_TEXT_LENGTH: usize = 2_000;

/// Maximum tag display_name length.
pub const MAX_TAG_NAME_LENGTH: usize = 100;

/// Maximum reminder window in seconds (1 year).
pub const MAX_REMINDER_WINDOW_SECONDS: i64 = 365 * 24 * 3600;

/// Mood / energy_level scale bounds (daily reviews).
pub const MOOD_MIN: i64 = 1;
pub const MOOD_MAX: i64 = 5;

/// Maximum number of tags attached to a single task. Promoted from
/// the CLI / MCP / Tauri shadows so all four write surfaces share one
/// source of truth (#2811).
pub const MAX_TASK_TAGS: usize = 30;

/// Maximum number of `depends_on` edges per task. Promoted from the
/// CLI / MCP shadows so both write surfaces share one source of truth
/// (#2811).
pub const MAX_TASK_DEPENDENCIES: usize = 50;

/// Maximum length of the optional habit `cue` field (the "context /
/// trigger" string surfaced next to a habit name — e.g. "After
/// morning coffee"). The React UI caps the input at
/// 200 codepoints via `MAX_HABIT_CUE_LENGTH` in
/// `shared/src/validation.ts` while the MCP / Tauri / CLI write
/// surfaces only enforced a 2000-char short-text bound, so a peer
/// writing a 1500-char cue silently truncated in every UI surface.
/// Promoting the cap to the domain layer means every write surface
/// rejects an over-200 cue at the validation boundary.
pub const MAX_HABIT_CUE_LENGTH: usize = 200;

/// Maximum list description length, measured in Unicode codepoints.
/// List descriptions render in list-picker chrome and side-rail
/// summaries — short metadata, not free-form prose — so the cap is
/// tighter than [`MAX_BODY_LENGTH`] (50 KB, used for free-form task
/// bodies). The 1 KB ceiling is shared by every write surface (MCP
/// create/update, Tauri create/update, import upserts) so a peer
/// cannot plant a multi-screen description that wedges every list
/// view displaying it.
pub const MAX_LIST_DESCRIPTION_LENGTH: usize = 1_000;

/// Maximum number of active reminders per task. The 20-row cap is
/// declared here as the single source of truth; every write surface
/// (`mcp-server/src/system/vec_limits/`,
/// `lorvex-cli/src/commands/mutate/reminders/effects.rs`,
/// `app/src-tauri/src/commands/tasks/reminders/create.rs`) re-exports
/// rather than redeclaring, so a future bump is a one-line change.
pub const MAX_REMINDERS_PER_TASK: usize = 20;

// ---------------------------------------------------------------------------
// Key/value caps for KV-style entities
// ---------------------------------------------------------------------------

/// Maximum length of a preference / device_state / memory key,
/// measured in Unicode codepoints. The single source of truth for
/// every key-shaped column the KV-style entities use — the Tauri
/// preferences / device_state surfaces, the MCP server contract, and
/// the CLI all re-export this constant rather than redeclaring it, so
/// a future bump is a one-line change.
pub const KV_KEY_MAX_CHARS: usize = 200;

/// Maximum length of a preference / device_state JSON value,
/// measured in bytes. Companion to [`KV_KEY_MAX_CHARS`] — every write
/// surface re-exports this constant directly.
pub const KV_VALUE_MAX_BYTES: usize = 50_000;

/// Maximum length of a human-seeded memory key, measured in Unicode
/// codepoints. Tighter than [`KV_KEY_MAX_CHARS`] (200) because
/// human-seeded keys flow through a short text input field and are
/// meant to stay readable as memory section titles (#2415). Issue
/// #3010 F11 promoted from the Tauri-only
/// `MAX_HUMAN_MEMORY_KEY_LENGTH` constant.
pub const MEMORY_KEY_MAX_CHARS: usize = 64;
