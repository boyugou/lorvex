use super::*;
use crate::runtime::change_tracking::execute_mcp_mutation;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::Patch;
use lorvex_store::repositories::list_repo::{self, ListUpdatePatch};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};

/// Mutation descriptor for the MCP `update_list` tool — Phase 2
/// migration of #3452. Captures the `ListUpdatePatch` shape, the
/// pre-mutation row, and the resolved updated-name string used for the
/// audit summary. The `apply` impl owns the version mint, the gated
/// `update_list_patched` call, and the post-fetch.
struct UpdateListMutation<'a> {
    list_id: &'a str,
    patch: ListUpdatePatch<'a>,
    updated_name: &'a str,
    before: &'a Value,
    now: &'a str,
}

impl<'a> Mutation for UpdateListMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let id_typed = lorvex_domain::ListId::from_trusted(self.list_id.to_string());
        list_repo::update_list_patched(conn, &id_typed, &self.patch, &version, self.now)?;

        // Read the post-mutation row pre-stamp shape — symmetric with the
        // `before` snapshot used as `before_json`.
        let after = crate::json_row::query_one_as_json(
            conn,
            "SELECT * FROM lists WHERE id = ?",
            [self.list_id.to_string()],
        )
        .map_err(|e| StoreError::Invariant(format!("query_one_as_json: {e}")))?
        .ok_or_else(|| StoreError::Invariant(format!("list '{}' vanished", self.list_id)))?;

        let summary = format!("Updated list \"{}\"", self.updated_name);
        Ok(MutationOutput::new(after, summary))
    }
}

pub(crate) fn update_list(conn: &Connection, args: UpdateListArgs) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let UpdateListArgs {
        id,
        name,
        color,
        icon,
        description,
        ai_notes,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "update_list",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // Unicode hygiene (#2427): scrub free-text fields before validation.
    // The `Patch<String>` carries null-as-clear semantics which we must
    // preserve — `Patch::Clear` stays `Patch::Clear`; `Patch::Set(s)`
    // becomes `Patch::Set(sanitize(s))`.
    let name = name.map(|s| lorvex_domain::sanitize_user_text(&s));
    let description = description.map(|s| lorvex_domain::sanitize_user_text(&s));
    let ai_notes = ai_notes.map(|s| lorvex_domain::sanitize_user_text(&s));
    // scrub `icon` symmetric with `name`. The UI
    // renders icon inline next to the list name; bidi-spoofing is a
    // narrow but real surface and the create path now scrubs it
    // (M6 above). Update should not be a re-introduction vector.
    let icon = icon.map(|s| lorvex_domain::sanitize_user_text(&s));

    let before = query_one_as_json(conn, "SELECT * FROM lists WHERE id = ?", [id.clone()])?
        .ok_or_else(|| McpError::NotFound(format!("List '{id}' not found")))?;

    validate_optional_string_length(name.as_deref(), "name", MAX_TITLE_LENGTH)?;
    if let Some(ref n) = name {
        if n.trim().is_empty() {
            return Err(McpError::Validation(
                "list name must not be empty".to_string(),
            ));
        }
    }
    if let Patch::Set(ref d) = description {
        // list description caps at MAX_LIST_DESCRIPTION_LENGTH.
        validate_optional_string_length(
            Some(d.as_str()),
            "description",
            MAX_LIST_DESCRIPTION_LENGTH,
        )?;
    }
    if let Patch::Set(ref a) = ai_notes {
        validate_optional_string_length(Some(a.as_str()), "ai_notes", MAX_AI_NOTES_LENGTH)?;
    }
    if let Patch::Set(ref c) = color {
        validate_optional_string_length(Some(c.as_str()), "color", MAX_SHORT_TEXT_LENGTH)?;
        // route through the shared hex-color validator.
        lorvex_domain::validation::validate_hex_color(c)?;
    }
    if let Patch::Set(ref i) = icon {
        validate_optional_string_length(Some(i.as_str()), "icon", MAX_SHORT_TEXT_LENGTH)?;
    }

    let has_changes = name.is_some()
        || color.is_set_or_clear()
        || icon.is_set_or_clear()
        || description.is_set_or_clear()
        || ai_notes.is_set_or_clear();

    if !has_changes {
        // Cache the no-op response under the supplied idempotency key
        // so a retry returns the SAME body byte-for-byte. Returning
        // the pre-mutation `before` snapshot without `cache_record`
        // would let a second call with the same key re-load the row
        // and surface a DIFFERENT response if a different surface
        // wrote it between the two calls — violating the "all
        // successful responses are cached" invariant every other
        // write tool upholds.
        let response = serde_json::to_string(&before)?;
        crate::runtime::idempotency::record_if_keyed(
            conn,
            idempotency_key.as_deref(),
            "update_list",
            &request_repr,
            &response,
        )?;
        return Ok(response);
    }

    // Map the MCP `Patch<String>` args into the shared repo's ListUpdatePatch.
    let patch = ListUpdatePatch {
        name: name.as_deref(),
        color: color.as_deref(),
        icon: icon.as_deref(),
        description: description.as_deref(),
        ai_notes: ai_notes.as_deref(),
    };
    let now = utc_now_iso();

    // Use the updated name for the summary (it'll be written to the DB).
    let updated_name = name.as_deref().unwrap_or_else(|| {
        before
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
    });

    let mutation = UpdateListMutation {
        list_id: id.as_str(),
        patch,
        updated_name,
        before: &before,
        now: now.as_str(),
    };

    execute_mcp_mutation(conn, &mutation, "update_list", id.clone())?;

    // Re-fetch post-stamp for the response so the caller sees the
    // post-funnel version — symmetric with the pre-Phase 2 shape.
    let after = query_one_as_json(conn, "SELECT * FROM lists WHERE id = ?", [id.clone()])?
        .ok_or_else(|| McpError::NotFound(format!("List '{id}' not found")))?;

    let response = serde_json::to_string(&after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "update_list",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
