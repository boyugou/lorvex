//! Shared parsing for sync edge entity IDs.
//!
//! Sync relation edges use `left:right` IDs for two-column primary keys. Keep
//! parsing strict and centralized so FK preflight, apply handlers, version
//! lookup, and pending-inbox remaps all reject malformed IDs the same way.

use std::fmt;

use lorvex_domain::naming;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CompositeEdgeIdError {
    entity_id: String,
    colon_count: usize,
}

impl fmt::Display for CompositeEdgeIdError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "edge entity_id must contain exactly one ':' separator with non-empty halves, \
             got {} separator(s) in {:?}",
            self.colon_count, self.entity_id
        )
    }
}

impl std::error::Error for CompositeEdgeIdError {}

pub(crate) fn is_composite_edge_entity_type(entity_type: &str) -> bool {
    matches!(
        entity_type,
        naming::EDGE_TASK_TAG
            | naming::EDGE_TASK_DEPENDENCY
            | naming::EDGE_TASK_CALENDAR_EVENT_LINK
            | naming::EDGE_HABIT_COMPLETION
    )
}

pub(crate) fn split_composite_edge_id(
    entity_id: &str,
) -> Result<(&str, &str), CompositeEdgeIdError> {
    let colon_count = entity_id.bytes().filter(|b| *b == b':').count();
    let Some((left, right)) = entity_id.split_once(':') else {
        return Err(CompositeEdgeIdError {
            entity_id: entity_id.to_string(),
            colon_count,
        });
    };
    if colon_count != 1 || left.is_empty() || right.is_empty() {
        return Err(CompositeEdgeIdError {
            entity_id: entity_id.to_string(),
            colon_count,
        });
    }
    Ok((left, right))
}

pub(crate) fn remap_composite_edge_id(
    original: &str,
    old_part: &str,
    new_part: &str,
) -> Result<Option<String>, CompositeEdgeIdError> {
    let (left, right) = split_composite_edge_id(original)?;
    let new_left = if left == old_part { new_part } else { left };
    let new_right = if right == old_part { new_part } else { right };
    if new_left == left && new_right == right {
        return Ok(None);
    }
    Ok(Some(format!("{new_left}:{new_right}")))
}

#[cfg(test)]
mod tests;
