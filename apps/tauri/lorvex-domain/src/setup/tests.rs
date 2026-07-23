use super::{derive_setup_readiness, SetupReadinessInput};

#[test]
fn setup_requires_working_hours_for_prerequisite_completion() {
    let readiness = derive_setup_readiness(&SetupReadinessInput {
        explicit_setup_completed: false,
        list_count: 1,
        default_list_ready: true,
        working_hours_ready: false,
    });

    assert!(readiness.lists_ready);
    assert!(readiness.normal_task_creation_ready);
    assert!(!readiness.prerequisites_ready);
    assert!(!readiness.setup_completed);
}

#[test]
fn explicit_setup_completed_overrides_missing_prerequisites() {
    let readiness = derive_setup_readiness(&SetupReadinessInput {
        explicit_setup_completed: true,
        list_count: 0,
        default_list_ready: false,
        working_hours_ready: false,
    });

    assert!(!readiness.prerequisites_ready);
    assert!(readiness.setup_completed);
}
