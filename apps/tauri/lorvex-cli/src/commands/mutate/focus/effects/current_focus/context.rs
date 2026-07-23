use crate::models::CurrentFocusView;

pub(super) const CURRENT_FOCUS_TASK_IDS_MAX: usize = 50;

#[derive(Debug, Clone)]
pub(super) enum CurrentFocusMutation {
    Set {
        task_ids: Vec<String>,
        briefing: Option<String>,
    },
    Add {
        task_ids: Vec<String>,
        briefing: Option<String>,
    },
    Remove {
        task_id: String,
    },
}

pub(super) struct FocusUpdateContext<'a> {
    pub(super) device_id: &'a str,
    pub(super) focus_date: &'a str,
    pub(super) timezone: &'a str,
    pub(super) now: &'a str,
    pub(super) before_focus: Option<CurrentFocusView>,
    pub(super) before_row_present: bool,
}
