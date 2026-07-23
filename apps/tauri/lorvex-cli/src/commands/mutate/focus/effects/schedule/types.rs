use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct FocusScheduleBlockInput {
    pub(super) block_type: String,
    pub(super) start_time: String,
    pub(super) end_time: String,
    pub(super) task_id: Option<String>,
    pub(super) event_id: Option<String>,
    pub(super) title: Option<String>,
}
