use tauri::WebviewWindow;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AuxiliaryWindowKind {
    Popover,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AuxiliaryWindowState {
    Hidden,
    Presented,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct AuxiliaryWindowSpacePolicy {
    visible_on_all_workspaces: bool,
    fullscreen_auxiliary: bool,
}

const fn auxiliary_window_space_policy(
    kind: AuxiliaryWindowKind,
    state: AuxiliaryWindowState,
) -> AuxiliaryWindowSpacePolicy {
    match (kind, state) {
        (_, AuxiliaryWindowState::Hidden) => AuxiliaryWindowSpacePolicy {
            visible_on_all_workspaces: false,
            fullscreen_auxiliary: false,
        },
        (AuxiliaryWindowKind::Popover, AuxiliaryWindowState::Presented) => {
            AuxiliaryWindowSpacePolicy {
                visible_on_all_workspaces: true,
                fullscreen_auxiliary: true,
            }
        }
    }
}

pub(crate) fn apply_auxiliary_window_space_state(
    window: &WebviewWindow,
    kind: AuxiliaryWindowKind,
    state: AuxiliaryWindowState,
) -> Result<(), String> {
    let policy = auxiliary_window_space_policy(kind, state);
    crate::platform::window_management::apply_workspace_policy(
        window,
        policy.visible_on_all_workspaces,
        policy.fullscreen_auxiliary,
    )
    .map_err(String::from)
}

#[cfg(test)]
mod tests;
