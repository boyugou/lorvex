extension AppStore {
  var appleSurfaceDiagnostics: AppleSurfaceDiagnostics {
    AppleSurfaceDiagnostics(
      spotlightIndexedTaskCount: lastSpotlightIndexedTaskCount,
      spotlightIndexedCalendarEventCount: lastSpotlightIndexedCalendarEventCount,
      spotlightTaskIndexErrorMessage: lastSpotlightTaskIndexErrorMessage,
      spotlightContentIndexErrorMessage: lastSpotlightContentIndexErrorMessage,
      scheduledReminderCount: lastScheduledReminderCount,
      taskReminderScheduleReport: lastTaskReminderScheduleReport,
      habitReminderScheduleReport: lastHabitReminderScheduleReport,
      widgetSnapshot: lastPublishedWidgetSnapshot,
      lastCalendarImportReport: lastCalendarImportReport,
      importedCalendarEventCount: lastImportedCalendarEventCount
    )
  }
}
