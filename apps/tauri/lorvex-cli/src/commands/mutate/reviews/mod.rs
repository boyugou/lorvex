use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::render::render_daily_review;

pub(crate) mod effects;
use effects::{
    add_daily_review_with_conn, amend_daily_review_with_conn, DailyReviewAddFields,
    DailyReviewAmendFields,
};

pub(crate) fn run_review_add(
    fields: DailyReviewAddFields<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let review = add_daily_review_with_conn(&mut conn, fields)?;
    match format {
        OutputFormat::Text => render_daily_review(Some(&review), &db_path, format),
        // canonical mutation envelope. Wraps the same
        // `review` body that `render_daily_review` would emit so JSON
        // consumers see a uniform shape across mutate + query surfaces.
        OutputFormat::Json => {
            render_mutation_envelope("review.add", &db_path, json!({ "review": review }))
        }
    }
}

pub(crate) fn run_review_amend(
    fields: DailyReviewAmendFields<'_>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;

    let review = amend_daily_review_with_conn(&mut conn, fields)?;
    match format {
        OutputFormat::Text => render_daily_review(Some(&review), &db_path, format),
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope("review.amend", &db_path, json!({ "review": review }))
        }
    }
}
