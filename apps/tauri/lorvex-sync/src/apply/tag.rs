//! Tag-specific apply handler with lookup_key convergence detection.
//!
//! After upserting a tag, the handler checks whether another tag with the same
//! `lookup_key` already exists. If so, the tag with the smaller (lexicographic)
//! `id` wins: the loser's `task_tags` rows are re-pointed to the winner, and
//! the loser row is deleted + tombstoned.

//! The submodules below `use super::*;` to pick up these imports —
//! that glob is the canonical sharing channel, not a stylistic choice.

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming;
use lorvex_domain::tag::normalize_lookup_key;
use rusqlite::{named_params, Connection};

use super::device_identity::read_local_device_hlc_suffix;
use super::merge_hlc::mint_merge_hlc_after;
use super::{ApplyError, LwwTieBreak};
use crate::tombstone::create_tombstone;

mod handlers;
mod merge;
mod payload;
#[cfg(test)]
mod tests;

pub(crate) use handlers::{apply_tag_delete, apply_tag_upsert};

use merge::merge_duplicate_tags;
use payload::{nullable_str_or_clear, optional_str_preserving_empty, required_str};
