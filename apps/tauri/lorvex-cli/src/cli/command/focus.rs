//! Daily focus + focus-schedule arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum FocusCommand {
    Show {
        date: Option<String>,
        format: OutputFormat,
    },
    Set {
        date: Option<String>,
        task_ids: Vec<String>,
        briefing: Option<String>,
        format: OutputFormat,
    },
    Add {
        date: Option<String>,
        task_ids: Vec<String>,
        briefing: Option<String>,
        format: OutputFormat,
    },
    Remove {
        date: Option<String>,
        task_id: String,
        format: OutputFormat,
    },
    Clear {
        date: Option<String>,
        format: OutputFormat,
    },
    ScheduleGet {
        date: Option<String>,
        format: OutputFormat,
    },
    SchedulePropose {
        date: Option<String>,
        format: OutputFormat,
    },
    ScheduleSave {
        date: Option<String>,
        blocks_json: String,
        rationale: Option<String>,
        format: OutputFormat,
    },
}
