use std::num::NonZeroU32;

use crate::startup_maintenance::open_db_at_path;
use lorvex_domain::naming::EntityKind;
use lorvex_runtime::resolve_db_path;
use lorvex_store::repositories::ai_changelog_query::{self, AiChangelogQuery};

use crate::cli::OutputFormat;
use crate::render::render_ai_changelog;

const AI_CHANGELOG_LIMIT_DEFAULT: u32 = 50;
const AI_CHANGELOG_LIMIT_CAP: u32 = 200;

pub(crate) fn run_changelog(
    limit: u32,
    entity_type: Option<String>,
    operation: Option<String>,
    entity_id: Option<String>,
    since: Option<String>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let limit = match limit {
        0 => AI_CHANGELOG_LIMIT_DEFAULT,
        value => value.min(AI_CHANGELOG_LIMIT_CAP),
    };
    // the clamp above guarantees a non-zero value, but
    // the fallback to `AI_CHANGELOG_LIMIT_DEFAULT` is a defensive
    // belt-and-suspenders guard so the `NonZeroU32` invariant never
    // fires a panic if the clamp logic changes.
    let limit_nz = NonZeroU32::new(limit).unwrap_or_else(|| {
        NonZeroU32::new(AI_CHANGELOG_LIMIT_DEFAULT)
            .expect("AI_CHANGELOG_LIMIT_DEFAULT must be non-zero")
    });
    let mut query = AiChangelogQuery::new(limit_nz);
    if let Some(value) = entity_type {
        // Parse the user-supplied entity_type filter at the CLI
        // boundary so the store always receives a typed `EntityKind`
        // and unknown values surface as a clear validation error.
        let kind = EntityKind::try_parse(&value).map_err(|err| {
            crate::error::CliError::Validation(format!(
                "--entity-type {value:?} is not a known entity kind: {err}"
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
    let entries = ai_changelog_query::list_ai_changelog(&conn, &query)?;
    render_ai_changelog(&db_path, &entries, limit, format)
}
