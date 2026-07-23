use super::*;
use crate::runtime::change_tracking::execute_mcp_mutation;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_store::repositories::list_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};

struct CreateListMutation {
    id: lorvex_domain::ListId,
    name: String,
    color: Option<String>,
    icon: Option<String>,
    description: Option<String>,
    ai_notes: Option<String>,
}

impl Mutation for CreateListMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_LIST
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        list_repo::create_list_with_ai_notes(
            conn,
            list_repo::ListCreateParams {
                id: &self.id,
                name: &self.name,
                color: self.color.as_deref(),
                icon: self.icon.as_deref(),
                description: self.description.as_deref(),
                ai_notes: self.ai_notes.as_deref(),
                version: &version,
            },
        )?;

        let list = query_one_as_json(
            conn,
            "SELECT * FROM lists WHERE id = ?",
            [self.id.to_string()],
        )
        .map_err(|error| StoreError::Invariant(error.to_string()))?
        .ok_or_else(|| {
            StoreError::Invariant(format!("Failed to load created list '{}'", self.id))
        })?;
        let summary = format!(
            "Created list \"{}\"{}",
            self.name,
            self.icon
                .as_ref()
                .map(|icon| format!(" {icon}"))
                .unwrap_or_default()
        );
        Ok(MutationOutput::new(list, summary))
    }
}

pub(crate) fn create_list(conn: &Connection, mut args: CreateListArgs) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint of the unmutated args so a retry returns the cached
    // response without re-creating the list (which would generate a
    // duplicate UUID + audit row + sync envelope on each replay).
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.take();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "create_list",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // Unicode hygiene (#2427): strip bidi overrides / zero-width / line
    // separators and normalize to NFC on every free-text field.
    args.name = lorvex_domain::sanitize_user_text(&args.name);
    args.description = args
        .description
        .map(|s| lorvex_domain::sanitize_user_text(&s));
    args.ai_notes = args.ai_notes.map(|s| lorvex_domain::sanitize_user_text(&s));
    // `icon` accepts emoji + arbitrary short text the
    // UI renders inline next to list names. Bidi-spoofing here is a
    // narrow but real surface — symmetric with `name` sanitization.
    args.icon = args.icon.map(|s| lorvex_domain::sanitize_user_text(&s));

    if args.name.trim().is_empty() {
        return Err(McpError::Validation(
            "list name must not be empty".to_string(),
        ));
    }
    validate_string_length(&args.name, "name", MAX_TITLE_LENGTH)?;
    // list description caps at MAX_LIST_DESCRIPTION_LENGTH
    // (1 KB), not the 50 KB task-body cap.
    validate_optional_string_length(
        args.description.as_deref(),
        "description",
        MAX_LIST_DESCRIPTION_LENGTH,
    )?;
    validate_optional_string_length(args.ai_notes.as_deref(), "ai_notes", MAX_AI_NOTES_LENGTH)?;
    validate_optional_string_length(args.color.as_deref(), "color", MAX_SHORT_TEXT_LENGTH)?;
    // list color is interpolated into UI inline
    // styles, so the shape check matters — match the calendar/task
    // discipline by routing through the shared hex-color validator.
    if let Some(color) = args.color.as_deref() {
        lorvex_domain::validation::validate_hex_color(color)?;
    }
    validate_optional_string_length(args.icon.as_deref(), "icon", MAX_SHORT_TEXT_LENGTH)?;
    let id = new_uuid();
    let id_typed = lorvex_domain::ListId::from_trusted(id.clone());
    let mutation = CreateListMutation {
        id: id_typed,
        name: args.name,
        color: args.color,
        icon: args.icon,
        description: args.description,
        ai_notes: args.ai_notes,
    };
    let output = execute_mcp_mutation(conn, &mutation, "create_list", id)?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "create_list",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
