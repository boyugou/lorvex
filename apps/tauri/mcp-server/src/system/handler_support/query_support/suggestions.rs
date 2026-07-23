//! Did-you-mean suggestion machinery for task-not-found errors (#2371).
//!
//! Split out of `query_support/mod.rs` so the prefix/substring scans, the
//! `Did you mean: …` trailer renderer, and the enriched
//! `McpError::NotFound` constructor live together — independent of the
//! enrichment / fetch pipeline that consumes them.

use super::task_id::{escape_like, looks_like_uuid};
use crate::error::McpError;

/// Collect up to 3 suggested `(id, title)` pairs that the assistant may
/// have meant when it passed `needle`. Two strategies, in order:
///
/// 1. **Prefix on `id`** — covers truncation typos.
/// 2. **Substring on `title`** — covers the case where the assistant
///    pasted a title fragment into an id field.
///
/// The second strategy is suppressed when `needle` looks UUID-shaped;
/// in that case an unrelated title hit would be noise rather than
/// signal. All queries use parameter binding so the caller-supplied
/// `needle` is never interpolated into SQL.
pub(super) fn task_suggestions(conn: &rusqlite::Connection, needle: &str) -> Vec<(String, String)> {
    const MAX_SUGGESTIONS: usize = 3;
    if needle.is_empty() {
        return Vec::new();
    }
    let escaped = escape_like(needle);
    let mut out: Vec<(String, String)> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    // Both LIKE scans go through `prepare_cached` so the plan is
    // amortized across the multi-id error-enrichment loop in
    // `fetch_tasks_json_batch` (one missing id => N LIKE scans
    // pre-cache; one prepared plan reused N times after). The
    // suggestion path is best-effort: a transient DB failure here
    // should silently degrade to "no suggestions" rather than
    // mask the underlying "task not found" error the caller is
    // already rendering.

    // Strategy 1: prefix match on id.
    let prefix_pattern = format!("{escaped}%");
    if let Ok(mut stmt) = conn.prepare_cached(
        "SELECT id, title FROM tasks \
         WHERE id LIKE ?1 ESCAPE '\\' \
         ORDER BY id ASC LIMIT 3",
    ) {
        if let Ok(rows) = stmt.query_map([&prefix_pattern], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        }) {
            for row in rows.flatten() {
                if seen.insert(row.0.clone()) {
                    out.push(row);
                    if out.len() >= MAX_SUGGESTIONS {
                        return out;
                    }
                }
            }
        }
    }

    // Strategy 2: substring on title — only when the needle does not
    // look like a UUID (otherwise it's almost certainly a truncation,
    // not a title fragment).
    if looks_like_uuid(needle) {
        return out;
    }
    let substring_pattern = format!("%{escaped}%");
    if let Ok(mut stmt) = conn.prepare_cached(
        "SELECT id, title FROM tasks \
         WHERE title LIKE ?1 ESCAPE '\\' \
         ORDER BY id ASC LIMIT 3",
    ) {
        if let Ok(rows) = stmt.query_map([&substring_pattern], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        }) {
            for row in rows.flatten() {
                if seen.insert(row.0.clone()) {
                    out.push(row);
                    if out.len() >= MAX_SUGGESTIONS {
                        return out;
                    }
                }
            }
        }
    }

    out
}

/// Render suggestion tuples as a single `Did you mean: ...` trailer.
/// Titles are truncated to 40 chars so the overall message stays bounded
/// (the outer `sanitize_error_message` caps at 256 chars anyway, but we
/// want all three suggestions to fit).
pub(super) fn format_suggestions(suggestions: &[(String, String)]) -> String {
    const TITLE_CAP: usize = 40;
    let parts: Vec<String> = suggestions
        .iter()
        .map(|(id, title)| {
            let display_title: String = if title.chars().count() > TITLE_CAP {
                let truncated: String = title.chars().take(TITLE_CAP).collect();
                format!("{truncated}…")
            } else {
                title.clone()
            };
            format!("{id} '{display_title}'")
        })
        .collect();
    parts.join(" · ")
}

/// Build a `McpError::NotFound` for a missing task id, enriched with up
/// to three suggestions drawn from the local task set (#2371). The
/// returned message preserves the legacy `"Task 'xxx' not found"`
/// prefix so `extract_quoted_id` still populates `entity_id` on the
/// structured MCP boundary; the suggestion trailer follows after a
/// period + space so the two halves are easy to parse by humans and
/// machines alike.
pub(crate) fn task_not_found_with_suggestions(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> McpError {
    let base = super::super::not_found_error("Task", task_id);
    let suggestions = task_suggestions(conn, task_id);
    let message = if suggestions.is_empty() {
        base
    } else {
        format!(
            "{base}. Did you mean: {}?",
            format_suggestions(&suggestions)
        )
    };
    McpError::NotFound(message)
}
