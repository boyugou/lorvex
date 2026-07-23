//! Pure input validation for task fields.
//!
//! Mirrors the defense-in-depth checks from MCP task validation and
//! `mcp-server/src/system/vec_limits/`, using the same constants so both
//! write surfaces reject identical inputs.

use crate::error::{AppError, AppResult};

// ── Constants ───────────────────────────────────────────────────────
//
// title / body lengths re-export from lorvex-domain so
// the app, MCP server, and domain share one source of truth. ai_notes
// / short_text / memory still live here because no
// cross-crate consumer needed them yet — promoting them is a clean
// follow-up when any of them needs to be referenced from another
// crate.

/// Maximum character count for title fields (task title).
const MAX_TITLE_LENGTH: usize = lorvex_domain::validation::MAX_TITLE_LENGTH;
/// Maximum character count for body/description fields.
const MAX_BODY_LENGTH: usize = lorvex_domain::validation::MAX_BODY_LENGTH;
/// Maximum character count for list descriptions. Distinct from
/// [`MAX_BODY_LENGTH`] because list descriptions render in list-picker
/// chrome and side-rail summaries — short metadata, not free-form
/// prose.
const MAX_LIST_DESCRIPTION_LENGTH: usize = lorvex_domain::validation::MAX_LIST_DESCRIPTION_LENGTH;
/// Maximum character count for short metadata fields (each tag, raw_input, etc.).
const MAX_SHORT_TEXT_LENGTH: usize = 2_000;
/// Maximum character count for memory section content.
/// Hoisted to `lorvex-domain` so sync apply enforces the same cap (#2429).
const MAX_MEMORY_CONTENT_LENGTH: usize = lorvex_domain::memory::MAX_MEMORY_CONTENT_LENGTH;

// ── Title ───────────────────────────────────────────────────────────

/// Validate that a task title is non-empty and within the length limit.
///
/// Emit `"task title must not be empty"` (lowercase `task`) so the
/// wording matches the MCP server's task-mutation prepared inputs and
/// the CLI's task-capture effects. AI clients parsing validation
/// errors get a single canonical phrasing across every write surface.
///
/// Also reject titles that are visually empty after stripping
/// zero-width / bidi / control codepoints — the same gate
/// `lorvex_domain::validation::validate_title` enforces. A bare
/// `trim().is_empty()` check would let a title made entirely of
/// `\u{200B}` / `\u{FEFF}` / `\u{202E}` padding slip past whenever
/// the call site forgot to run `sanitize_user_text` upstream (tests,
/// future sync-apply callers, etc.). The wording stays exactly as
/// H2 standardized so AI clients pattern-matching on the empty-error
/// string don't see a new fork.
pub fn validate_task_title(title: &str) -> AppResult<()> {
    if title.trim().is_empty() || lorvex_domain::validation::is_visually_empty(title) {
        return Err(AppError::Validation(
            "task title must not be empty".to_string(),
        ));
    }
    validate_string_length(title, "title", MAX_TITLE_LENGTH)
}

// ── Body ────────────────────────────────────────────────────────────

/// Validate that a task body, if present, is within the length limit.
pub fn validate_task_body(body: Option<&str>) -> AppResult<()> {
    validate_optional_string_length(body, "body", MAX_BODY_LENGTH)
}

// ── Priority ────────────────────────────────────────────────────────

/// Validate that priority, if set, is in the 1-3 range.
///
/// Issue #2994 H4 (also closes L12): emit the same `"Invalid
/// priority '{p}'. Expected one of: 1|2|3"` wording the MCP server
/// uses, and source the allow-list display + bounds from the shared
/// domain constants so the four write surfaces no longer drift on
/// the sentence shape or on the bound numbers.
pub fn validate_task_priority(priority: Option<i64>) -> AppResult<()> {
    use lorvex_domain::validation::{
        PRIORITY_MAX, PRIORITY_MIN, TASK_PRIORITY_ALLOWED_VALUES_DISPLAY,
    };
    if let Some(p) = priority {
        if !(PRIORITY_MIN..=PRIORITY_MAX).contains(&p) {
            return Err(AppError::Validation(format!(
                "Invalid priority '{p}'. Expected one of: {TASK_PRIORITY_ALLOWED_VALUES_DISPLAY}"
            )));
        }
    }
    Ok(())
}

// ── Tags ────────────────────────────────────────────────────────────

/// Validate tag count and per-tag length from a parsed slice.
pub fn validate_task_tags(tags: Option<&[String]>) -> AppResult<()> {
    let Some(items) = tags else {
        return Ok(());
    };
    if items.len() > lorvex_domain::validation::MAX_TASK_TAGS {
        return Err(AppError::Validation(format!(
            "Too many tags ({} items, limit {})",
            items.len(),
            lorvex_domain::validation::MAX_TASK_TAGS
        )));
    }
    for tag in items {
        validate_string_length(tag, "tag", MAX_SHORT_TEXT_LENGTH)?;
    }
    Ok(())
}

// ── List fields ────────────────────────────────────────────────────

/// Validate list name length (same limit as task title — both use MAX_TITLE_LENGTH).
pub fn validate_list_name(name: &str) -> AppResult<()> {
    validate_string_length(name, "name", MAX_TITLE_LENGTH)
}

/// Validate list description length.
///
/// List descriptions render inline in list-picker chrome (sidebar,
/// list switcher) and are capped at the dedicated 1 KB
/// [`MAX_LIST_DESCRIPTION_LENGTH`] so the Tauri write path matches
/// the MCP server and import upserts on the same bound. Reusing the
/// 50 KB [`MAX_BODY_LENGTH`] would let list-picker rows render a
/// novel-sized blob.
pub fn validate_list_description(description: Option<&str>) -> AppResult<()> {
    validate_optional_string_length(description, "description", MAX_LIST_DESCRIPTION_LENGTH)
}

/// Validate that a free-form color field is a 7-character `#rrggbb`
/// hex string. Routes through
/// `lorvex_domain::validation::validate_hex_color` so MCP / CLI /
/// Tauri all accept the same shape — a length-only check would let a
/// peer (or a non-color-picker IPC caller) plant a 2 KB string into
/// `lists.color` and have the UI silently render it as garbage CSS.
pub fn validate_color_hex(value: Option<&str>) -> AppResult<()> {
    let Some(v) = value else {
        return Ok(());
    };
    lorvex_domain::validation::validate_hex_color(v)
        .map_err(|e| AppError::Validation(e.to_string()))
}

/// Validate short metadata fields (color, icon, etc.).
///
/// the field name flows into the typed
/// `ValidationError::TooLong { field: &'static str, .. }`, so this
/// signature requires a `&'static str` argument. Every existing
/// caller passes a literal so this is a transparent narrowing.
pub fn validate_short_text(value: Option<&str>, field_name: &'static str) -> AppResult<()> {
    validate_optional_string_length(value, field_name, MAX_SHORT_TEXT_LENGTH)
}

// ── Memory ─────────────────────────────────────────────────────────

/// Validate memory content length.
pub fn validate_memory_content(content: &str) -> AppResult<()> {
    validate_string_length(content, "content", MAX_MEMORY_CONTENT_LENGTH)
}

// ── Helpers (private) ───────────────────────────────────────────────
//
// the triple-declared `validate_string_length` /
// `validate_optional_string_length` shadows in this crate, in
// `commands/habits/queries/writes.rs`, and in
// `mcp-server/src/tasks/validation.rs` were promoted to
// `lorvex_domain::validation::{validate_string_length,
// validate_optional_string_length}`. Both helpers return
// `Result<(), ValidationError>` and convert into `AppError` via the
// existing `From<ValidationError>` impl in `crate::error`, so the
// signature change is transparent to call sites. Wording is preserved
// (`"{field} exceeds maximum length ({n} chars, limit {max})"`)
// because `ValidationError::TooLong` Display was aligned in the same
// commit (#2994 H1 had already unified the wording across the three
// surfaces; only the helper duplication remained).

fn validate_string_length(value: &str, field_name: &'static str, max_len: usize) -> AppResult<()> {
    lorvex_domain::validation::validate_string_length(value, field_name, max_len)
        .map_err(AppError::from)
}

fn validate_optional_string_length(
    value: Option<&str>,
    field_name: &'static str,
    max_len: usize,
) -> AppResult<()> {
    lorvex_domain::validation::validate_optional_string_length(value, field_name, max_len)
        .map_err(AppError::from)
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests;
