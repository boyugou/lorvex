import MCP

enum ContentToolDefinitions {
  static let all: [ToolDefinition] = [
    .read(18, ListHabitToolCatalog.getListsTool) {
      try await $0.listsResult(arguments: $1)
    },
    .write(19, ListHabitToolCatalog.createListTool) {
      try await $0.createListResult(arguments: $1)
    },
    .write(20, ListHabitToolCatalog.updateListTool) {
      try await $0.updateListResult(arguments: $1)
    },
    .write(21, ListHabitToolCatalog.setListAINotesTool) {
      try await $0.setListAINotesResult(arguments: $1)
    },
    .write(22, ListHabitToolCatalog.deleteListTool) {
      try await $0.deleteListResult(arguments: $1)
    },
    .write(23, ListHabitToolCatalog.archiveListTool) {
      try await $0.archiveListResult(arguments: $1)
    },
    .write(24, ListHabitToolCatalog.unarchiveListTool) {
      try await $0.unarchiveListResult(arguments: $1)
    },
    .read(25, ListHabitToolCatalog.getListTool) {
      try await $0.getListResult(arguments: $1)
    },
    .read(26, ListHabitToolCatalog.getListHealthSnapshotTool) { registry, _ in
      try await registry.getListHealthSnapshotResult()
    },
    .write(27, ListHabitToolCatalog.reorderListsTool) {
      try await $0.reorderListsResult(arguments: $1)
    },
    .read(28, ListHabitToolCatalog.listAllTagsTool) { registry, _ in
      try await registry.listAllTagsResult()
    },
    .write(29, ListHabitToolCatalog.renameTagTool) {
      try await $0.renameTagResult(arguments: $1)
    },
    .write(30, ListHabitToolCatalog.deleteTagTool) {
      try await $0.deleteTagResult(arguments: $1)
    },
    .write(31, ListHabitToolCatalog.mergeTagsTool) {
      try await $0.mergeTagsResult(arguments: $1)
    },
    .read(38, ReviewToolCatalog.dailyReviewTool) {
      try await $0.dailyReviewResult(arguments: $1)
    },
    .read(39, ReviewToolCatalog.weeklyReviewBriefTool) {
      try await $0.weeklyReviewBriefResult(arguments: $1)
    },
    .read(40, CalendarToolCatalog.timelineTool) {
      try await $0.calendarTimelineResult(arguments: $1)
    },
    .write(41, CalendarToolCatalog.createEventTool) {
      try await $0.createCalendarEventResult(arguments: $1)
    },
    .write(42, CalendarToolCatalog.batchCreateEventsTool) {
      try await $0.batchCreateCalendarEventsResult(arguments: $1)
    },
    .write(43, CalendarLinksToolCatalog.updateEventTool) {
      try await $0.updateCalendarEventResult(arguments: $1)
    },
    .write(44, CalendarLinksToolCatalog.deleteEventTool) {
      try await $0.deleteCalendarEventResult(arguments: $1)
    },
    .read(45, CalendarLinksToolCatalog.searchEventsTool) {
      try await $0.searchCalendarEventsResult(arguments: $1)
    },
    .write(46, CalendarLinksToolCatalog.linkTaskToEventTool) {
      try await $0.linkTaskToEventResult(arguments: $1)
    },
    .write(47, CalendarLinksToolCatalog.unlinkTaskFromEventTool) {
      try await $0.unlinkTaskFromEventResult(arguments: $1)
    },
    .write(48, CalendarLinksToolCatalog.linkTaskToProviderEventTool) {
      try await $0.linkTaskToProviderEventResult(arguments: $1)
    },
    .write(49, CalendarLinksToolCatalog.unlinkTaskFromProviderEventTool) {
      try await $0.unlinkTaskFromProviderEventResult(arguments: $1)
    },
    .read(50, CalendarLinksToolCatalog.linkedEventsForTaskTool) {
      try await $0.linkedEventsForTaskResult(arguments: $1)
    },
    .read(51, CalendarLinksToolCatalog.linkedTasksForEventTool) {
      try await $0.linkedTasksForEventResult(arguments: $1)
    },
    .write(52, CalendarLinksToolCatalog.addEventExceptionTool) {
      try await $0.addCalendarEventExceptionResult(arguments: $1)
    },
    .write(53, CalendarLinksToolCatalog.removeEventExceptionTool) {
      try await $0.removeCalendarEventExceptionResult(arguments: $1)
    },
    .write(54, CalendarLinksToolCatalog.editScopedEventTool) {
      try await $0.editScopedCalendarEventResult(arguments: $1)
    },
    .write(55, CalendarLinksToolCatalog.deleteScopedEventTool) {
      try await $0.deleteScopedCalendarEventResult(arguments: $1)
    },
    .read(56, IcsExportToolCatalog.exportCalendarIcsTool) {
      try await $0.exportCalendarIcsResult(arguments: $1)
    },
    .write(58, ReviewToolCatalog.addDailyReviewTool) {
      try await $0.addDailyReviewResult(arguments: $1)
    },
    .write(59, ReviewToolCatalog.amendDailyReviewTool) {
      try await $0.amendDailyReviewResult(arguments: $1)
    },
    .read(60, ReviewToolCatalog.reviewHistoryTool) {
      try await $0.reviewHistoryResult(arguments: $1)
    },
    .read(61, MemoryToolCatalog.readMemoryTool) {
      try await $0.memoryResult(arguments: $1)
    },
    .write(62, MemoryToolCatalog.writeMemoryTool) {
      try await $0.writeMemoryResult(arguments: $1)
    },
    .write(63, MemoryToolCatalog.renameMemoryTool) {
      try await $0.renameMemoryResult(arguments: $1)
    },
    .write(64, MemoryExtendedToolCatalog.deleteMemoryTool) {
      try await $0.deleteMemoryResult(arguments: $1)
    },
  ]
}
