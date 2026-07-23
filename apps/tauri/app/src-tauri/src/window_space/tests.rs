use super::{
    auxiliary_window_space_policy, AuxiliaryWindowKind, AuxiliaryWindowSpacePolicy,
    AuxiliaryWindowState,
};

#[test]
fn presented_popover_policy_is_fullscreen_eligible() {
    assert_eq!(
        auxiliary_window_space_policy(
            AuxiliaryWindowKind::Popover,
            AuxiliaryWindowState::Presented,
        ),
        AuxiliaryWindowSpacePolicy {
            visible_on_all_workspaces: true,
            fullscreen_auxiliary: true,
        },
    );
}

#[test]
fn hidden_auxiliary_policy_clears_cross_space_and_fullscreen_affinity() {
    assert_eq!(
        auxiliary_window_space_policy(AuxiliaryWindowKind::Popover, AuxiliaryWindowState::Hidden),
        AuxiliaryWindowSpacePolicy {
            visible_on_all_workspaces: false,
            fullscreen_auxiliary: false,
        },
    );
}
