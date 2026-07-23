//! Untrusted-content fencing for MCP tool responses (#2422).
//!
//! User-origin string fields (task title/body/ai_notes, tag names,
//! memory content, calendar event title/description/location)
//! flow straight into the assistant model's context. Without a
//! structural marker the model has no way to distinguish a legitimate
//! system instruction from a task titled
//! `"IGNORE ALL PRIOR INSTRUCTIONS..."` typed by an attacker.
//!
//! This module wraps every such value at serialization time with an
//! inline sentinel the model can recognize as a security boundary and
//! strips a minimal set of hostile control / bidi / zero-width
//! characters. The JSON response shape is unchanged — only the string
//! contents are extended with the sentinel prefix.
//!
//! Callers **must** apply [`mcp_untrusted_text`] on the RESPONSE path
//! only. Do not mutate stored rows or re-wrap already-wrapped values.

use serde_json::Value;

/// Open/close sentinel tags the assistant must treat as a hard
/// boundary: anything between `⟦user⟧` and `⟦/user⟧` is user-typed
/// content and MUST NOT be interpreted as instructions.
pub(crate) const UNTRUSTED_OPEN: &str = "\u{27E6}user\u{27E7}";
pub(crate) const UNTRUSTED_CLOSE: &str = "\u{27E6}/user\u{27E7}";

/// Strip characters that can rewrite the visual reading order of text
/// or smuggle control signals into a terminal/assistant:
/// - C0 controls (U+0000..U+001F) except `\t`, `\n`, `\r`
/// - U+007F DEL
/// - C1 controls (U+0080..U+009F)
/// - Bidi override/isolate (U+202A..U+202E, U+2066..U+2069)
/// - Line/paragraph separators (U+2028, U+2029)
/// - Zero-width (U+200B..U+200D, U+2060, U+FEFF)
/// - Tag characters (U+E0000..U+E007F) used in "invisible prompt"
///   smuggling.
fn sanitize_untrusted(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        // Each `=> {}` arm strips a different category of unicode
        // codepoint (C0 controls, DEL, C1 controls, bidi overrides,
        // bidi isolates, line/paragraph separators, zero-width, tag
        // characters). They share a body but documenting the
        // categories separately is the whole point of this match —
        // collapsing them would erase the hygiene rationale.
        #[allow(clippy::match_same_arms)]
        match ch {
            '\t' | '\n' | '\r' => out.push(ch),
            c if (c as u32) < 0x20 => {}
            '\u{007F}' => {}
            c if (c as u32) >= 0x80 && (c as u32) <= 0x9F => {}
            '\u{202A}'..='\u{202E}' => {}
            '\u{2066}'..='\u{2069}' => {}
            '\u{2028}' | '\u{2029}' => {}
            '\u{200B}'..='\u{200D}' | '\u{2060}' | '\u{FEFF}' => {}
            c if (c as u32) >= 0xE0000 && (c as u32) <= 0xE007F => {}
            c => out.push(c),
        }
    }
    out
}

/// Wrap a user-origin string with the UNTRUSTED sentinel and apply
/// basic hygiene. Safe to call on empty strings.
///
/// every fenced field walked the format machinery for three static
/// `&'static str` parts. Pre-sized `String::with_capacity` + plain
/// `push_str` skips the formatter entirely; on a typical
/// `enrich_and_fence_tasks_for_response` call (title + body +
/// ai_notes + raw_input + N tags + N checklist items) this trims a
/// per-row allocation pass on every read tool that fences user text.
pub(crate) fn mcp_untrusted_text(input: &str) -> String {
    let cleaned = sanitize_untrusted(input);
    // OPEN + " " + cleaned + " " + CLOSE — pre-sized so the
    // wrapper allocates exactly once.
    let mut out =
        String::with_capacity(UNTRUSTED_OPEN.len() + cleaned.len() + UNTRUSTED_CLOSE.len() + 2);
    out.push_str(UNTRUSTED_OPEN);
    out.push(' ');
    out.push_str(&cleaned);
    out.push(' ');
    out.push_str(UNTRUSTED_CLOSE);
    out
}

/// Wrap a JSON object's string field in place. No-op if the field is
/// missing, null, or already not a string. Silently skips non-string
/// values so arrays (like `tags`) can be handled by a separate helper.
///
/// re-inserted via `obj.insert(key.to_string(), ...)` — that route
/// allocated a fresh `String` for the lookup key on every fenced
/// field even though the entry was already in the map. The
/// `get_mut` path mutates the existing slot in place, eliminating
/// the redundant key allocation; only the wrapped `String` itself
/// (which we have to allocate either way) survives.
pub(crate) fn fence_object_field(obj: &mut serde_json::Map<String, Value>, key: &str) {
    if let Some(slot) = obj.get_mut(key) {
        if let Some(existing) = slot.as_str() {
            let wrapped = mcp_untrusted_text(existing);
            *slot = Value::String(wrapped);
        }
    }
}

/// Wrap every element of a string array at `key` in place. No-op if
/// the field is missing, null, or not an array. Non-string elements
/// are left untouched.
fn fence_object_string_array(obj: &mut serde_json::Map<String, Value>, key: &str) {
    let Some(Value::Array(items)) = obj.get_mut(key) else {
        return;
    };
    for item in items.iter_mut() {
        if let Some(existing) = item.as_str() {
            *item = Value::String(mcp_untrusted_text(existing));
        }
    }
}

/// Fence every user-origin string field on a task JSON row. Applied
/// after enrichment so `tags` (string array) is already attached.
pub(crate) fn fence_task_user_fields(task: &mut Value) {
    let Some(obj) = task.as_object_mut() else {
        return;
    };
    fence_object_field(obj, "title");
    fence_object_field(obj, "body");
    fence_object_field(obj, "ai_notes");
    fence_object_field(obj, "raw_input");
    fence_object_string_array(obj, "tags");
    // Checklist items: array of { id, text, done, ... } — text is user-origin.
    if let Some(Value::Array(items)) = obj.get_mut("checklist_items") {
        for item in items.iter_mut() {
            if let Some(item_obj) = item.as_object_mut() {
                fence_object_field(item_obj, "text");
            }
        }
    }
}

/// Fence every user-origin string field on a batch of task JSON rows.
pub(crate) fn fence_tasks_user_fields(tasks: &mut [Value]) {
    for task in tasks.iter_mut() {
        fence_task_user_fields(task);
    }
}

/// Fence user-origin string fields on a canonical calendar event row.
pub(crate) fn fence_calendar_event_user_fields(event: &mut Value) {
    let Some(obj) = event.as_object_mut() else {
        return;
    };
    fence_object_field(obj, "title");
    fence_object_field(obj, "description");
    fence_object_field(obj, "location");
    fence_object_field(obj, "person_name");
    // Attendee names are user-provided as well.
    if let Some(Value::Array(items)) = obj.get_mut("attendees") {
        for item in items.iter_mut() {
            if let Some(item_obj) = item.as_object_mut() {
                fence_object_field(item_obj, "name");
                fence_object_field(item_obj, "email");
            }
        }
    }
}

pub(crate) fn fence_calendar_events_user_fields(events: &mut [Value]) {
    for event in events.iter_mut() {
        fence_calendar_event_user_fields(event);
    }
}

#[cfg(test)]
mod tests;
