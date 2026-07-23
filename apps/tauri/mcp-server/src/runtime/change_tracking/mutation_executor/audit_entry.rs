//! Per-entity audit row for multi-emit mutations.

use serde_json::Value;

/// One per-entity audit row in a multi-emit mutation
/// (see [`super::core::execute_with_audit_entries`]).
pub(crate) struct MutationAuditEntry {
    pub(crate) entity_id: String,
    pub(crate) before: Option<Value>,
    pub(crate) after: Value,
    pub(crate) summary: String,
}

impl MutationAuditEntry {
    pub(crate) fn new(
        entity_id: impl Into<String>,
        after: Value,
        summary: impl Into<String>,
    ) -> Self {
        Self {
            entity_id: entity_id.into(),
            before: None,
            after,
            summary: summary.into(),
        }
    }
}
