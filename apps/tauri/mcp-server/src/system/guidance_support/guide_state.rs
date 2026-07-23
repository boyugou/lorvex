use crate::contract::GuideTopic;
use lorvex_domain::preference_keys::PREF_WORKING_HOURS;
use serde_json::{json, Value};

#[derive(Debug, Clone)]
pub(crate) struct GuideState {
    pub(crate) setup_completed: bool,
    pub(crate) task_count: i64,
    pub(crate) list_count: i64,
    pub(crate) has_current_focus: bool,
    pub(crate) memory_count: i64,
    pub(crate) configured_preferences: Vec<String>,
}

impl GuideState {
    pub(crate) fn to_value(&self) -> Value {
        json!({
            "setup_completed": self.setup_completed,
            "task_count": self.task_count,
            "list_count": self.list_count,
            "has_current_focus": self.has_current_focus,
            "memory_count": self.memory_count,
            "configured_preferences": self.configured_preferences,
        })
    }
}

pub(crate) const fn auto_detect_guide_topic(state: &GuideState) -> GuideTopic {
    if !state.setup_completed {
        return GuideTopic::GettingStarted;
    }
    if state.task_count == 0 {
        return GuideTopic::TaskManagement;
    }
    if state.list_count == 0 {
        return GuideTopic::Lists;
    }
    if !state.has_current_focus && state.task_count >= 3 {
        return GuideTopic::CurrentFocus;
    }
    GuideTopic::Overview
}

pub(crate) fn guide_suggested_actions(state: &GuideState) -> Vec<String> {
    let mut actions: Vec<String> = Vec::new();
    if !state.has_current_focus && state.task_count >= 3 {
        actions.push("Set your current focus - \"plan my day\"".to_string());
    }
    if state.task_count == 0 {
        actions.push("Start adding tasks - tell me what is on your mind".to_string());
    }
    if state.list_count == 0 && state.task_count > 5 {
        actions.push("Organize tasks into lists".to_string());
    }
    if !state
        .configured_preferences
        .iter()
        .any(|key| key == PREF_WORKING_HOURS)
    {
        actions.push("Set your working hours - \"I work 9am to 6pm\"".to_string());
    }
    if state.memory_count == 0 {
        actions.push("Tell me about yourself so I can personalize your experience".to_string());
    }
    if actions.is_empty() {
        actions.push("Ask \"how was my week?\" for a weekly review".to_string());
        actions.push("Add new tasks or adjust existing ones".to_string());
    }
    actions
}
