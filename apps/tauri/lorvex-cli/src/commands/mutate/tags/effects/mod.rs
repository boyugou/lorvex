use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TAG, ENTITY_TASK, OP_DELETE, OP_UPSERT};
use lorvex_domain::validation::MAX_TASK_TAGS;
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::tag_repo;
use lorvex_sync::outbox_enqueue::{
    enqueue_entity_upsert, enqueue_payload_delete, enqueue_payload_upsert,
};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::json;

mod normalization;
mod outbox;
mod rename;
mod rows;

use normalization::normalize_single_tag_name;
pub(crate) use normalization::{normalize_capture_tags, validate_task_tag_count};
pub(crate) use outbox::enqueue_copied_tag_edges;
pub(crate) use rename::rename_tag_with_conn;
#[cfg(test)]
pub(crate) use rename::TagRenameResult;
use rows::{load_task_tag_edges_by_tag_id, TaskTagEdgeWithTaskRow};

#[cfg(test)]
mod tests;
