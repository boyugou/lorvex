use super::*;

pub(crate) fn enqueue_copied_tag_edges(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    edges: &[lorvex_workflow::lifecycle::CopiedTagEdge],
) -> Result<(), crate::error::CliError> {
    for edge in edges {
        let version = hlc_state.generate().to_string();
        let entity_id = format!("{}:{}", edge.task_id, edge.tag_id);
        let task_id = lorvex_domain::TaskId::from_trusted(edge.task_id.clone());
        let tag_id = lorvex_domain::TagId::from_trusted(edge.tag_id.clone());
        let payload = lorvex_store::payload_loaders::task_tag_payload(
            &task_id,
            &tag_id,
            &edge.version,
            &edge.created_at,
        );
        enqueue_payload_upsert(
            conn,
            EDGE_TASK_TAG,
            &entity_id,
            &payload,
            crate::commands::shared::bare_outbox_ctx(&version, device_id),
        )?;
    }
    Ok(())
}
