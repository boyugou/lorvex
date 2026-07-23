use crate::composite_edge::split_composite_edge_id;

use super::super::ApplyError;

pub(super) fn split_composite_id(entity_id: &str) -> Result<(&str, &str), ApplyError> {
    split_composite_edge_id(entity_id).map_err(|err| ApplyError::InvalidPayload(err.to_string()))
}

// JSON-extraction primitives now live in `apply::json_helpers`
//; re-export so existing `super::helpers::*`
// call sites in this folder don't need touching.
pub(super) use super::super::json_helpers::{optional_str, required_i64, required_str};
