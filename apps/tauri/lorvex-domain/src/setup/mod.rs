#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupReadinessInput {
    pub explicit_setup_completed: bool,
    pub list_count: i64,
    pub default_list_ready: bool,
    pub working_hours_ready: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupReadiness {
    pub lists_ready: bool,
    pub default_list_ready: bool,
    pub working_hours_ready: bool,
    pub normal_task_creation_ready: bool,
    pub prerequisites_ready: bool,
    pub explicit_setup_completed: bool,
    pub setup_completed: bool,
}

pub const fn derive_setup_readiness(input: &SetupReadinessInput) -> SetupReadiness {
    let lists_ready = input.list_count > 0;
    let normal_task_creation_ready = lists_ready && input.default_list_ready;
    let prerequisites_ready = normal_task_creation_ready && input.working_hours_ready;
    let setup_completed = input.explicit_setup_completed || prerequisites_ready;

    SetupReadiness {
        lists_ready,
        default_list_ready: input.default_list_ready,
        working_hours_ready: input.working_hours_ready,
        normal_task_creation_ready,
        prerequisites_ready,
        explicit_setup_completed: input.explicit_setup_completed,
        setup_completed,
    }
}

#[cfg(test)]
mod tests;
