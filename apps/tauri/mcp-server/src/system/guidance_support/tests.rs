use super::{auto_detect_guide_topic, severity_by_count, GuideState};
use crate::contract::GuideTopic;
use lorvex_domain::preference_keys::PREF_WORKING_HOURS;

fn base_state() -> GuideState {
    GuideState {
        setup_completed: true,
        task_count: 4,
        list_count: 1,
        has_current_focus: true,
        memory_count: 1,
        configured_preferences: vec![PREF_WORKING_HOURS.to_string()],
    }
}

#[test]
#[serial_test::serial(hlc)]
fn auto_detect_guide_topic_prioritizes_getting_started_before_other_states() {
    let mut state = base_state();
    state.setup_completed = false;
    assert_eq!(auto_detect_guide_topic(&state), GuideTopic::GettingStarted);
}

#[test]
#[serial_test::serial(hlc)]
fn auto_detect_guide_topic_prefers_current_focus_when_no_plan() {
    let mut state = base_state();
    state.has_current_focus = false;
    assert_eq!(auto_detect_guide_topic(&state), GuideTopic::CurrentFocus);
}

#[test]
#[serial_test::serial(hlc)]
fn severity_by_count_uses_threshold_buckets() {
    assert_eq!(severity_by_count(10, 8, 4), "high");
    assert_eq!(severity_by_count(5, 8, 4), "medium");
    assert_eq!(severity_by_count(1, 8, 4), "low");
}
