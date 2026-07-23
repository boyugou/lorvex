use super::gate::require_memory_unlocked;
use super::key::normalize_mcp_memory_key;
use crate::contract::ReadMemoryArgs;
use crate::error::McpError;
use crate::json_row::{query_all_as_json, query_one_as_json};
use lorvex_domain::memory::MEMORY_KEY_NOTES_FOR_AI;
use lorvex_domain::text_sanitize::strip_dangerous_codepoints;
use rusqlite::Connection;
use serde_json::{json, Map, Value};

/// Truncate a string to at most `max_chars` Unicode scalar values.
/// Returns the (possibly truncated) string and whether truncation occurred.
pub(super) fn truncate_preview_chars(content: &str, max_chars: usize) -> (String, bool) {
    if max_chars == 0 {
        return if content.is_empty() {
            (String::new(), false)
        } else {
            ("…".to_string(), true)
        };
    }
    let char_count = content.chars().count();
    if char_count <= max_chars {
        (content.to_string(), false)
    } else {
        let truncated: String = content.chars().take(max_chars).collect();
        (format!("{truncated}…"), true)
    }
}

/// Prefix every preview returned by `read_memory_session_summary`. The
/// marker exists so the assistant treats synced memory entries as
/// peer-supplied data rather than as instructions from the user — see
/// #2429.
pub(crate) const UNTRUSTED_MEMORY_MARKER: &str =
    "--- MEMORY ENTRY (untrusted peer-supplied content) ---\n";

/// Wrap a memory-entry content preview so the assistant parses it as a
/// literal string, not as inline markdown / directives.
///
/// Steps, in order (all deliberate; see #2429):
///
/// 1. Strip C0/C1 control, bidi, and zero-width codepoints via the shared
///    helper in `lorvex-domain` (reused from #2425).
/// 2. Apply `truncate_preview_chars` so previews stay within the caller's
///    requested char budget (sanitization can only ever shrink the input,
///    so truncation still matches the documented budget).
/// 3. Replace any bare triple-backtick runs in the sanitized content with
///    a zero-width sequence so the attacker can't pre-terminate our fence
///    and smuggle real markdown back out.
/// 4. Wrap in a triple-backtick `text` fenced block.
/// 5. Prepend [`UNTRUSTED_MEMORY_MARKER`].
pub(super) fn render_entry_preview(raw: &str, preview_chars: usize) -> (String, bool) {
    let sanitized = strip_dangerous_codepoints(raw);
    let (trimmed, truncated) = truncate_preview_chars(&sanitized, preview_chars);
    // Neutralize any `\`\`\`` the attacker embedded so our fence stays
    // intact. We replace the three literal backticks with three backticks
    // each separated by a zero-width space equivalent — but since we just
    // stripped zero-width codepoints above, use a different neutralizer:
    // insert a single space between the backticks so the terminator no
    // longer matches ```.
    let fence_safe = trimmed.replace("```", "` ` `");
    let fenced = format!("```text\n{fence_safe}\n```");
    let marked = format!("{UNTRUSTED_MEMORY_MARKER}{fenced}");
    (marked, truncated)
}

/// Bounded memory summary for session startup.
/// Returns the most recently updated entries with truncated content previews,
/// with the `notes_for_ai` entry separated out.
/// also gate the session-summary read path. This is
/// invoked from `get_session_context`; without the gate, the AI can
/// observe locked memory through that side channel.
pub(crate) fn read_memory_session_summary(
    conn: &Connection,
    limit: usize,
    preview_chars: usize,
) -> Result<serde_json::Value, McpError> {
    require_memory_unlocked(conn)?;
    // Read notes_for_ai separately
    let notes_for_ai =
        lorvex_store::repositories::memory_repo::get_memory_entry(conn, MEMORY_KEY_NOTES_FOR_AI)?;

    // `notes_for_ai` is human-owned content from the local user; we still
    // sanitize C0/C1/bidi/zero-width because those characters are never
    // legitimate in user-authored notes, but we don't fence or add the
    // untrusted marker — treating the user's own notes as a prompt-injection
    // vector would make the feature unusable. The untrusted marker applies
    // only to peer-synced entries below (#2429).
    let notes_for_ai_value = notes_for_ai.map(|entry| {
        let sanitized = strip_dangerous_codepoints(&entry.content);
        let (content_preview, preview_truncated) =
            truncate_preview_chars(&sanitized, preview_chars);
        json!({
            "content_preview": content_preview,
            "preview_truncated": preview_truncated,
            "updated_at": entry.updated_at,
        })
    });

    // Read AI-generated entries (exclude notes_for_ai)
    let mut stmt = conn.prepare_cached(
        "SELECT key, content, updated_at FROM memories \
             WHERE key != ?1 \
             ORDER BY updated_at DESC, key ASC \
             LIMIT ?2",
    )?;

    let total: i64 = conn
        .prepare_cached("SELECT COUNT(*) FROM memories WHERE key != ?1")?
        .query_row([MEMORY_KEY_NOTES_FOR_AI], |row| row.get(0))?;

    let entries: Vec<serde_json::Value> = stmt
        .query_map(
            rusqlite::params![MEMORY_KEY_NOTES_FOR_AI, limit as i64],
            |row| {
                let key: String = row.get(0)?;
                let content: String = row.get(1)?;
                let updated_at: String = row.get(2)?;
                // Peer-supplied content — sanitize, fence, and mark as
                // untrusted so model treats it as data, not instructions
                // (#2429).
                let (content_preview, preview_truncated) =
                    render_entry_preview(&content, preview_chars);
                Ok(json!({
                    "key": key,
                    "updated_at": updated_at,
                    "content_preview": content_preview,
                    "preview_truncated": preview_truncated,
                }))
            },
        )?
        .collect::<Result<Vec<_>, _>>()?;

    let returned = entries.len() as i64;
    Ok(json!({
        "notes_for_ai": notes_for_ai_value,
        "total_entries": total,
        "returned": returned,
        "truncated": total > returned,
        "entries": entries,
    }))
}

pub(crate) fn read_memory(conn: &Connection, args: ReadMemoryArgs) -> Result<String, McpError> {
    require_memory_unlocked(conn)?;
    let ReadMemoryArgs { key } = args;
    if let Some(key) = key {
        let key = normalize_mcp_memory_key(&key)?;
        let row = query_one_as_json(conn, "SELECT * FROM memories WHERE key = ?", [key.clone()])?;
        return match row {
            Some(mut row) => {
                // #2422: memory content is authored by the AI but may
                // contain user-pasted text; fence it as untrusted.
                if let Some(obj) = row.as_object_mut() {
                    crate::system::text_hygiene::fence_object_field(obj, "content");
                }
                Ok(serde_json::to_string(&row)?)
            }
            None => Ok(serde_json::to_string(
                &json!({ "key": key, "content": null, "updated_at": null }),
            )?),
        };
    }

    let rows = query_all_as_json(conn, "SELECT * FROM memories ORDER BY key", [])?;

    let mut entries = Map::new();
    for row in rows {
        let Value::Object(mut row_obj) = row else {
            continue;
        };
        let Some(key) = row_obj
            .remove("key")
            .and_then(|v| v.as_str().map(ToString::to_string))
        else {
            continue;
        };
        let content = row_obj.remove("content").unwrap_or(Value::Null);
        let content = match content {
            Value::String(s) => Value::String(crate::system::text_hygiene::mcp_untrusted_text(&s)),
            other => other,
        };
        let updated_at = row_obj.remove("updated_at").unwrap_or(Value::Null);
        entries.insert(
            key,
            json!({
                "content": content,
                "updated_at": updated_at,
            }),
        );
    }
    Ok(serde_json::to_string(&json!({ "entries": entries }))?)
}
