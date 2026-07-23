use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ExportAllDataArgs {
    #[schemars(
        description = "Optional output file path for the ZIP archive. If omitted, writes to {data_dir}/exports/lorvex-export-v1-{timestamp}.zip"
    )]
    pub(crate) output_path: Option<String>,
    #[schemars(
        description = "Optional scoped export categories. Allowed values: tasks, lists, calendar, habits, daily_reviews, memory, preferences, focus, subscriptions, audit. Omit or pass an empty array for a full export."
    )]
    pub(crate) scope_categories: Option<Vec<String>>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ImportDataArgs {
    #[schemars(
        description = "Absolute file path to a lorvex-export ZIP archive (produced by export_all_data)"
    )]
    pub(crate) file_path: String,
    /// #2368: when true, parse + validate the archive and return a
    /// structured preview summary (per-entity-type would-change counts,
    /// manifest provenance, validation findings) WITHOUT writing to the
    /// database. Omit or pass `false` to commit as
    /// before. The preview itself is recorded in `ai_changelog` with
    /// `operation = "import_preview"` so the preview call is auditable.
    #[serde(default)]
    #[schemars(
        description = "If true, return a preview summary without applying changes. Use this first to show the user what would happen, then call again with dry_run=false (or omit) to commit."
    )]
    pub(crate) dry_run: bool,
}
