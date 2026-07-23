use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::EDGE_TASK_DEPENDENCY;
use lorvex_domain::validation::MAX_TASK_DEPENDENCIES;
use lorvex_sync::outbox_enqueue::enqueue_payload_delete;
use rusqlite::Connection;

pub(super) fn validate_task_dependency_count(
    deps: Option<&[String]>,
) -> Result<(), crate::error::CliError> {
    crate::commands::shared::validate_slice_max_len(deps, "depends_on", MAX_TASK_DEPENDENCIES)
}

pub(crate) fn enqueue_deleted_dependency_edges(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    edges: &[lorvex_workflow::lifecycle::DeletedDependencyEdge],
) -> Result<(), crate::error::CliError> {
    // the payload + entity_id encoders live in the
    // shared `lorvex_sync::outbox_enqueue` so this surface, the Tauri
    // `enqueue_deleted_dep_edges`, and the MCP
    // `enqueue_deleted_task_dependency_syncs` all emit byte-identical
    // dependency-edge tombstones. Issue #2969-H3 background: ship a
    // payload-bearing tombstone (the edge's full pre-delete row)
    // instead of an empty `{}` `enqueue_entity_delete`;
    // that missed the upsert envelope had no way to reconstruct the
    // row from a tombstone — the same correctness loss that #2818 /
    // #2903 / #2928-H1 fixed for sibling cascades.
    // `DeletedDependencyEdge` carries `created_at` + `version` captured
    // at the moment the cascade DELETE ran.
    for edge in edges {
        let entity_id = lorvex_sync::outbox_enqueue::encode_dependency_edge_entity_id(edge);
        let payload = lorvex_sync::outbox_enqueue::build_dependency_edge_delete_payload(edge);
        let version = hlc_state.generate().to_string();
        enqueue_payload_delete(
            conn,
            EDGE_TASK_DEPENDENCY,
            &entity_id,
            &payload,
            crate::commands::shared::bare_outbox_ctx(&version, device_id),
        )?;
    }
    Ok(())
}
