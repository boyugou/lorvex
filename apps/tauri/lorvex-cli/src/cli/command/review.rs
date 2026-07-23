//! Daily-review get/history/weekly/brief/add/amend arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ReviewCommand {
    Get {
        date: Option<String>,
        format: OutputFormat,
    },
    History {
        since: Option<String>,
        limit: u32,
        format: OutputFormat,
    },
    Weekly {
        completed_limit: u32,
        stalled_lists_limit: u32,
        deferred_limit: u32,
        someday_limit: u32,
        format: OutputFormat,
    },
    Brief {
        completed_limit: u32,
        stalled_lists_limit: u32,
        deferred_limit: u32,
        someday_limit: u32,
        format: OutputFormat,
    },
    Add {
        date: Option<String>,
        summary: String,
        mood: Option<u8>,
        energy_level: Option<u8>,
        wins: Option<String>,
        blockers: Option<String>,
        learnings: Option<String>,
        ai_synthesis: Option<String>,
        linked_task_ids: Vec<String>,
        linked_list_ids: Vec<String>,
        format: OutputFormat,
    },
    Amend {
        date: String,
        summary: Option<String>,
        mood: Option<u8>,
        energy_level: Option<u8>,
        wins: Option<String>,
        blockers: Option<String>,
        learnings: Option<String>,
        ai_synthesis: Option<String>,
        linked_task_ids: Option<Vec<String>>,
        linked_list_ids: Option<Vec<String>>,
        format: OutputFormat,
    },
}
