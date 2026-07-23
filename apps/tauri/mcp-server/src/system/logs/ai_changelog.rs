use std::num::NonZeroU32;

use crate::contract::{GetAiChangelogArgs, AI_CHANGELOG_LIMIT_CAP, AI_CHANGELOG_LIMIT_DEFAULT};
use crate::error::McpError;
use crate::system::handler_support::{bounded_limit_or_default, next_offset_for_page};
use lorvex_domain::naming::EntityKind;
use lorvex_store::repositories::ai_changelog_query::{self, AiChangelogQuery};
use rusqlite::Connection;
use serde_json::json;

pub(crate) fn get_ai_changelog(
    conn: &Connection,
    args: GetAiChangelogArgs,
) -> Result<String, McpError> {
    let GetAiChangelogArgs {
        limit,
        offset,
        entity_type,
        operation,
        entity_id,
        since,
    } = args;
    let limit = bounded_limit_or_default(limit, AI_CHANGELOG_LIMIT_DEFAULT, AI_CHANGELOG_LIMIT_CAP);
    let offset = offset.unwrap_or(0);
    // `bounded_limit_or_default` clamps `0` to the
    // typed default before reaching here, so the `NonZeroU32` cast
    // never fires the fallback branch in practice. The fallback to
    // `AI_CHANGELOG_LIMIT_DEFAULT` is a defensive belt-and-suspenders
    // guard against future drift in `bounded_limit_or_default`.
    //
    // widen the SQL `LIMIT` by the requested offset
    // and slice the result locally. `AiChangelogQuery` doesn't
    // expose an offset field; widening keeps the implementation
    // here without churning the store's UNION-DISTINCT query
    // shape. `AI_CHANGELOG_LIMIT_CAP` already bounds the cost.
    let widened_limit = limit.saturating_add(offset).min(AI_CHANGELOG_LIMIT_CAP);
    let widened_nonzero = NonZeroU32::new(widened_limit).unwrap_or_else(|| {
        NonZeroU32::new(AI_CHANGELOG_LIMIT_DEFAULT)
            .expect("AI_CHANGELOG_LIMIT_DEFAULT must be non-zero")
    });
    let mut query = AiChangelogQuery::new(widened_nonzero);
    if let Some(value) = entity_type {
        // Parse the user-supplied entity_type filter at the MCP
        // boundary so the store always receives a typed `EntityKind`
        // and unknown values surface as a clear validation error.
        let kind = EntityKind::try_parse(&value).map_err(|err| {
            McpError::UserMessage(format!(
                "entity_type {value:?} is not a known entity kind: {err}"
            ))
        })?;
        query = query.with_entity_type(kind);
    }
    if let Some(value) = operation {
        query = query.with_operation(value);
    }
    if let Some(value) = entity_id {
        query = query.with_entity_id(value);
    }
    if let Some(value) = since {
        query = query.with_since(value);
    }
    let mut entries = ai_changelog_query::list_ai_changelog(conn, &query)?;

    let offset_usize = offset as usize;
    if entries.len() > offset_usize {
        entries.drain(0..offset_usize);
    } else {
        entries.clear();
    }
    let limit_usize = limit as usize;
    let truncated = entries.len() > limit_usize;
    if entries.len() > limit_usize {
        entries.truncate(limit_usize);
    }
    let returned = entries.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(truncated, consumed, returned);

    let payload = json!({
        "limit": limit,
        "offset": offset,
        "count": entries.len(),
        "truncated": truncated,
        "next_offset": next_offset,
        "entries": entries,
    });
    Ok(serde_json::to_string(&payload)?)
}
