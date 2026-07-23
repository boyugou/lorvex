import MCP

enum TaskToolDefinitions {
  static let all: [ToolDefinition] = [
    .read(7, TaskToolCatalog.getTaskTool) {
      try await $0.taskDetailResult(arguments: $1)
    },
    .read(8, TaskToolCatalog.listTasksTool) {
      try await $0.listTasksResult(arguments: $1)
    },
    .read(9, TaskToolCatalog.searchTasksTool) {
      try await $0.searchTasksResult(arguments: $1)
    },
    .read(10, TaskToolCatalog.deferredTasksTool) {
      try await $0.deferredTasksResult(arguments: $1)
    },
    .write(11, TaskChecklistToolCatalog.addItemTool) {
      try await $0.addTaskChecklistItemResult(arguments: $1)
    },
    .write(12, TaskChecklistToolCatalog.toggleItemTool) {
      try await $0.toggleTaskChecklistItemResult(arguments: $1)
    },
    .write(13, TaskChecklistToolCatalog.updateItemTool) {
      try await $0.updateTaskChecklistItemResult(arguments: $1)
    },
    .write(14, TaskChecklistToolCatalog.removeItemTool) {
      try await $0.removeTaskChecklistItemResult(arguments: $1)
    },
    .write(15, TaskChecklistToolCatalog.reorderItemsTool) {
      try await $0.reorderTaskChecklistItemsResult(arguments: $1)
    },
    .write(16, TaskReminderToolCatalog.addReminderTool) {
      try await $0.addTaskReminderResult(arguments: $1)
    },
    .write(17, TaskReminderToolCatalog.removeReminderTool) {
      try await $0.removeTaskReminderResult(arguments: $1)
    },
    .write(69, TaskMutationToolCatalog.createTaskTool) {
      try await $0.createTaskResult(arguments: $1)
    },
    .write(70, BatchTaskToolCatalog.batchCreateTool) {
      try await $0.batchCreateTasksResult(arguments: $1)
    },
    .write(71, BatchTaskToolCatalog.batchUpdateTool) {
      try await $0.batchUpdateTasksResult(arguments: $1)
    },
    .write(72, TaskMutationToolCatalog.updateTaskTool) {
      try await $0.updateTaskResult(arguments: $1)
    },
    .write(73, TaskMutationToolCatalog.setTaskAINotesTool) {
      try await $0.setTaskAINotesResult(arguments: $1)
    },
    .write(74, TaskMutationToolCatalog.completeTaskTool) {
      try await $0.completeTaskResult(arguments: $1)
    },
    .write(75, TaskMutationToolCatalog.cancelTaskTool) {
      try await $0.setTaskStatusResult(arguments: $1, operation: .cancel)
    },
    .write(76, TaskMutationToolCatalog.permanentDeleteTaskTool) {
      try await $0.permanentDeleteTaskResult(arguments: $1)
    },
    .write(77, TaskMutationToolCatalog.archiveTaskTool) {
      try await $0.archiveTaskResult(arguments: $1)
    },
    .write(78, TaskMutationToolCatalog.unarchiveTaskTool) {
      try await $0.unarchiveTaskResult(arguments: $1)
    },
    .write(79, TaskMutationToolCatalog.reopenTaskTool) {
      try await $0.setTaskStatusResult(arguments: $1, operation: .reopen)
    },
    // Listing orders 116/117: the in_progress lifecycle pair, appended to the
    // contiguous global order while grouped with the complete/cancel/reopen
    // family they mirror.
    .write(116, TaskMutationToolCatalog.startTaskTool) {
      try await $0.setTaskStatusResult(arguments: $1, operation: .start)
    },
    .write(117, TaskMutationToolCatalog.pauseTaskTool) {
      try await $0.setTaskStatusResult(arguments: $1, operation: .pause)
    },
    .write(80, TaskMutationToolCatalog.setTaskSomedayTool) {
      try await $0.setTaskSomedayResult(arguments: $1)
    },
    .write(81, TaskMutationToolCatalog.deferTaskTool) {
      try await $0.deferTaskResult(arguments: $1)
    },
    .write(82, TaskMutationToolCatalog.batchDeferTasksTool) {
      try await $0.batchDeferTasksResult(arguments: $1)
    },
    .write(83, TaskMutationToolCatalog.moveTaskToListTool) {
      try await $0.moveTaskToListResult(arguments: $1)
    },
    .write(96, TaskRecurrenceToolCatalog.setRecurrenceTool) {
      try await $0.setTaskRecurrenceResult(arguments: $1)
    },
    .write(97, TaskRecurrenceToolCatalog.removeRecurrenceTool) {
      try await $0.removeTaskRecurrenceResult(arguments: $1)
    },
    .write(98, TaskRecurrenceToolCatalog.addExceptionTool) {
      try await $0.addTaskRecurrenceExceptionResult(arguments: $1)
    },
    .write(99, TaskRecurrenceToolCatalog.removeExceptionTool) {
      try await $0.removeTaskRecurrenceExceptionResult(arguments: $1)
    },
    .write(100, TaskBatchOpsToolCatalog.batchCompleteTool) {
      try await $0.batchCompleteTasksResult(arguments: $1)
    },
    .write(101, TaskBatchOpsToolCatalog.batchCancelTool) {
      try await $0.batchCancelTasksResult(arguments: $1)
    },
    .write(102, TaskMutationToolCatalog.batchCancelTasksInListTool) {
      try await $0.batchCancelTasksInListResult(arguments: $1)
    },
    .write(103, TaskBatchOpsToolCatalog.batchReopenTool) {
      try await $0.batchReopenTasksResult(arguments: $1)
    },
    .write(104, TaskBatchOpsToolCatalog.batchMoveTool) {
      try await $0.batchMoveTasksResult(arguments: $1)
    },
    .write(105, TaskBatchOpsToolCatalog.appendBodyTool) {
      try await $0.appendToTaskBodyResult(arguments: $1)
    },
    .write(106, TaskBatchOpsToolCatalog.setRemindersTool) {
      try await $0.setTaskRemindersResult(arguments: $1)
    },
    .read(112, TaskToolCatalog.dependencyGraphTool) {
      try await $0.dependencyGraphResult(arguments: $1)
    },
    .read(113, TaskToolCatalog.upcomingTasksTool) {
      try await $0.upcomingTasksResult(arguments: $1)
    },
    .read(114, TaskToolCatalog.dueTaskRemindersTool) {
      try await $0.dueTaskRemindersResult(arguments: $1)
    },
    .read(115, TaskToolCatalog.upcomingTaskRemindersTool) {
      try await $0.upcomingTaskRemindersResult(arguments: $1)
    },
  ]
}
