mod batch_create;
mod batch_lifecycle;
mod batch_move;
mod batch_update;
mod lifecycle;
mod lists;
mod queries;
mod single_create;
mod single_update;
mod status_value;

pub(crate) use batch_create::{BatchCreateTaskInput, BatchCreateTasksArgs};
pub(crate) use batch_lifecycle::{
    BatchCancelTasksArgs, BatchCompleteTasksArgs, BatchDeferTasksArgs, BatchReopenTasksArgs,
};
pub(crate) use batch_move::BatchMoveTasksArgs;
pub(crate) use batch_update::{BatchUpdateTaskPatch, BatchUpdateTasksArgs};
pub(crate) use lifecycle::{
    AddTaskChecklistItemArgs, AddTaskRecurrenceExceptionArgs, AddTaskReminderArgs,
    AppendToTaskBodyArgs, CancelTaskArgs, CompleteTaskArgs, DeferTaskArgs, PermanentDeleteTaskArgs,
    RecurrenceRuleArgs, RemoveTaskChecklistItemArgs, RemoveTaskRecurrenceExceptionArgs,
    RemoveTaskReminderArgs, ReopenTaskArgs, ReorderTaskChecklistItemsArgs, SetRecurrenceArgs,
    SetTaskAiNotesArgs, SetTaskRemindersArgs, ToggleTaskChecklistItemArgs,
    UpdateTaskChecklistItemArgs,
};
// `RecurrenceFreq` is only constructed by tests that build
// `RecurrenceRuleArgs` literals — production code only ever
// destructures `SetRecurrenceArgs.rule`. Gate the re-export on
// `cfg(test)` so the lib-only surface stays free of the
// shield-and-pretend `#[allow(unused_imports)]` that previously
// kept the import alive in non-test builds.
#[cfg(test)]
pub(crate) use lifecycle::RecurrenceFreq;
pub(crate) use lists::*;
pub(crate) use queries::{
    GetDeferredTasksArgs, GetDependencyGraphArgs, GetDueTaskRemindersArgs, GetTaskArgs,
    GetTasksByTagArgs, GetTodaysTasksArgs, GetUpcomingTaskRemindersArgs, GetUpcomingTasksArgs,
    ListAllTagsArgs, ListTasksArgs, ListTasksDueRangeArgs, ListTasksSortBy, RenameTagArgs,
    SearchTasksArgs, SortDirection, TaskStatusFilter,
};
pub(crate) use single_create::CreateTaskArgs;
pub(crate) use single_update::UpdateTaskArgs;
pub(crate) use status_value::TaskStatusValue;
