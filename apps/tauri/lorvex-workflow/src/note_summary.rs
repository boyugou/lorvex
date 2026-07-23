//! Single home for the "note-shaped" audit-summary builder used by
//! every surface that produces note-style task writes (`set_task_ai_notes`,
//! `append_to_task_body`).
//!
//! Both writes emit the same `"{verb} '{title}': {preview}{ellipsis}"`
//! audit summary. The Changelog UI groups note-shaped events by the
//! leading verb and truncates at the same 80-char preview boundary,
//! so every surface (MCP server, CLI, Tauri commands, sync apply)
//! MUST stay aligned. This crate is the single home for the helper so
//! every surface routes through one definition.

/// Maximum characters of the user-supplied note that appear in the
/// audit summary's preview.
pub const NOTE_SUMMARY_PREVIEW_MAX_CHARS: usize = 80;

/// Build a one-line audit summary for a "note-shaped" task write.
///
/// `verb` is the leading verb the Changelog UI groups by
/// (`"Added AI notes to"`, `"Appended note to"`). `title` is the task
/// title in single quotes. `note` is the raw, sanitized,
/// already-trimmed user-supplied text — it is rendered verbatim up to
/// [`NOTE_SUMMARY_PREVIEW_MAX_CHARS`] characters, with a trailing
/// `"..."` if the original text exceeded that bound.
pub fn note_summary(verb: &str, title: &str, note: &str) -> String {
    let preview: String = note.chars().take(NOTE_SUMMARY_PREVIEW_MAX_CHARS).collect();
    // `chars().nth(N).is_some()` short-circuits at the (N+1)-th
    // character; `chars().count() > N` walks the entire string. For
    // long notes (the common case for an LLM-emitted update) this is
    // ~5x faster — and the boundary is correct: the (N+1)-th char
    // existing means more than N chars are present, i.e. truncation
    // is needed.
    let truncated = note.chars().nth(NOTE_SUMMARY_PREVIEW_MAX_CHARS).is_some();
    format!(
        "{verb} '{title}': {preview}{}",
        if truncated { "..." } else { "" }
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_summary_short_text_is_not_truncated() {
        let s = note_summary("Added AI notes to", "design review", "Plan first");
        assert_eq!(s, "Added AI notes to 'design review': Plan first");
    }

    #[test]
    fn note_summary_long_text_is_truncated_with_ellipsis() {
        let long = "x".repeat(120);
        let s = note_summary("Appended note to", "task", &long);
        assert!(s.starts_with("Appended note to 'task': "));
        assert!(s.ends_with("..."));
        // Preview is exactly 80 chars + the trailing "..." marker.
        let preview_part = s
            .strip_prefix("Appended note to 'task': ")
            .unwrap()
            .strip_suffix("...")
            .unwrap();
        assert_eq!(preview_part.chars().count(), NOTE_SUMMARY_PREVIEW_MAX_CHARS);
    }

    #[test]
    fn note_summary_at_exact_boundary_is_not_marked_truncated() {
        let exactly_max = "y".repeat(NOTE_SUMMARY_PREVIEW_MAX_CHARS);
        let s = note_summary("Added AI notes to", "t", &exactly_max);
        assert!(!s.ends_with("..."));
    }

    #[test]
    fn note_summary_one_past_boundary_is_truncated() {
        let one_over = "z".repeat(NOTE_SUMMARY_PREVIEW_MAX_CHARS + 1);
        let s = note_summary("Added AI notes to", "t", &one_over);
        assert!(s.ends_with("..."));
    }
}
