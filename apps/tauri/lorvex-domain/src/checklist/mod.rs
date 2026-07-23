//! Task checklist domain helpers.
//!
//! Checklist items are first-class operational state. Markdown checkbox lines
//! inside task bodies are only a legacy import/migration source.

use crate::validation::ValidationError;

pub const MAX_TASK_CHECKLIST_ITEMS: usize = 200;
pub const MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH: usize = 1_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtractedMarkdownChecklistItem {
    pub position: i64,
    pub text: String,
    pub completed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MarkdownChecklistExtraction {
    pub remaining_body: String,
    pub items: Vec<ExtractedMarkdownChecklistItem>,
}

pub fn validate_task_checklist_item_text(text: &str) -> Result<(), ValidationError> {
    if text.trim().is_empty() {
        return Err(ValidationError::Empty("task_checklist_item.text"));
    }
    // count Unicode codepoints, not bytes. The
    // sister validators in `validation::text` (`validate_title`,
    // `validate_body`, `validate_tag_name`) all measure codepoints, and
    // the MCP / Tauri / TS surfaces do the same. Counting bytes here
    // rejected legitimate Chinese / emoji checklist items at ~1/3 of
    // the documented MAX while letting equivalent ASCII strings
    // through.
    let char_count = text.chars().count();
    if char_count > MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH {
        return Err(ValidationError::TooLong {
            field: "task_checklist_item.text",
            max: MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH,
            actual: char_count,
        });
    }
    Ok(())
}

pub const fn validate_task_checklist_item_count(count: usize) -> Result<(), ValidationError> {
    if count > MAX_TASK_CHECKLIST_ITEMS {
        return Err(ValidationError::OutOfRange {
            field: "task_checklist_items",
            min: 0,
            max: MAX_TASK_CHECKLIST_ITEMS as i64,
            actual: count as i64,
        });
    }
    Ok(())
}

pub fn extract_markdown_checklist(body: &str) -> MarkdownChecklistExtraction {
    let mut remaining_lines = Vec::new();
    let mut items = Vec::new();

    for line in body.lines() {
        let parsed = line
            .strip_prefix("- [ ] ")
            .map(|text| (false, text))
            .or_else(|| line.strip_prefix("- [x] ").map(|text| (true, text)))
            .or_else(|| line.strip_prefix("- [X] ").map(|text| (true, text)));

        if let Some((completed, text)) = parsed {
            let trimmed = text.trim();
            if !trimmed.is_empty()
                && validate_task_checklist_item_text(trimmed).is_ok()
                && validate_task_checklist_item_count(items.len() + 1).is_ok()
            {
                items.push(ExtractedMarkdownChecklistItem {
                    position: items.len() as i64,
                    text: trimmed.to_string(),
                    completed,
                });
                continue;
            }
        }

        remaining_lines.push(line);
    }

    MarkdownChecklistExtraction {
        remaining_body: remaining_lines.join("\n"),
        items,
    }
}

#[cfg(test)]
mod tests;
