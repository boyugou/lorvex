import Foundation
import LorvexCore
import LorvexStore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

// MARK: - Diagnostics report shape

@Test
func appleSurfaceDiagnosticsStatusCopyUsesLocalizationCatalog() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Support/AppleSurfaceDiagnostics.swift"),
    encoding: .utf8
  )

  #expect(source.contains(#"bundle: LorvexL10n.bundle"#))
  #expect(!source.contains(#".lorvex(key:"#))
  #expect(source.contains(#""settings.diagnostics.status.spotlight""#))
  #expect(source.contains(#""settings.diagnostics.status.reminders_scheduled_count""#))
  #expect(source.contains(#""settings.diagnostics.status.calendar_import_succeeded_count""#))
  #expect(source.contains(#""settings.diagnostics.status.widget_published""#))
  #expect(!source.contains(#"return "Disabled""#))
  #expect(!source.contains(#"return "Not started""#))
  #expect(!source.contains(#"return "Skipped""#))
}

@Test
func appleSurfaceDiagnosticsReportsNotStartedCalendarImport() {
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 0,
    spotlightIndexedCalendarEventCount: 0,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .disabled,
    widgetSnapshot: nil,
    lastCalendarImportReport: .notStarted,
    importedCalendarEventCount: 0
  )

  #expect(diagnostics.calendarImportStatus == "Not started")
  #expect(diagnostics.reminderStatus == "Disabled")
}

@Test
func appleSurfaceDiagnosticsReportsSuccessfulCalendarImport() {
  let report = CalendarIntegrationReport.succeeded(
    operation: "eventkit-import",
    eventCount: 7
  )
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 4,
    spotlightIndexedCalendarEventCount: 7,
    scheduledReminderCount: 1,
    taskReminderScheduleReport: .scheduled(1),
    widgetSnapshot: nil,
    lastCalendarImportReport: report,
    importedCalendarEventCount: 7
  )

  #expect(diagnostics.calendarImportStatus == "7 imported events")
  #expect(diagnostics.spotlightStatus == "4 tasks, 7 calendar events")
  #expect(diagnostics.reminderStatus == "1 scheduled reminder")
}

/// The Spotlight status is one sentence whose two counts each take their own
/// plural form.
@Test
func appleSurfaceDiagnosticsSpotlightStatusVariesEachCountOnItsOwn() {
  func status(tasks: Int, events: Int) -> String {
    AppleSurfaceDiagnostics(
      spotlightIndexedTaskCount: tasks,
      spotlightIndexedCalendarEventCount: events,
      scheduledReminderCount: 0,
      taskReminderScheduleReport: .disabled,
      widgetSnapshot: nil,
      lastCalendarImportReport: .notStarted,
      importedCalendarEventCount: 0
    ).spotlightStatus
  }

  #expect(status(tasks: 1, events: 1) == "1 task, 1 calendar event")
  #expect(status(tasks: 1, events: 2) == "1 task, 2 calendar events")
  #expect(status(tasks: 0, events: 1) == "0 tasks, 1 calendar event")
}

@Test
func appleSurfaceDiagnosticsReportsPublishedWidgetVersion() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: WidgetSnapshot.Stats(
      todayCount: 1,
      overdueCount: 0,
      dueTodayCount: 0
    ),
    briefing: nil,
    tasks: [
      .init(
        id: "diagnostics-task", title: "Published task", status: "open", dueDate: nil,
        priority: 2, listID: nil, estimatedMinutes: nil)
    ]
  )
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 0,
    spotlightIndexedCalendarEventCount: 0,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .disabled,
    widgetSnapshot: snapshot,
    lastCalendarImportReport: .notStarted,
    importedCalendarEventCount: 0
  )

  #expect(diagnostics.widgetStatus == "Published")
  #expect(diagnostics.widgetGeneratedAt == LorvexDateFormatters.iso8601.date(from: "2026-05-22T16:00:00Z"))
  #expect(diagnostics.widgetTodayTaskCount == 1)
}

@Test
func appleSurfaceDiagnosticsReportsTaskReminderSchedulingFailure() {
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 0,
    spotlightIndexedCalendarEventCount: 0,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .permissionDenied(requestedCount: 2),
    widgetSnapshot: nil,
    lastCalendarImportReport: .notStarted,
    importedCalendarEventCount: 0
  )

  #expect(diagnostics.reminderStatus == "Permission Denied")
}

@Test
func appleSurfaceDiagnosticsReportsHabitReminderStatusIndependently() {
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 0,
    spotlightIndexedCalendarEventCount: 0,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .disabled,
    habitReminderScheduleReport: .scheduled(2),
    widgetSnapshot: nil,
    lastCalendarImportReport: .notStarted,
    importedCalendarEventCount: 0
  )

  // The habit row reads its own report, not the task one's scheduled count.
  #expect(diagnostics.reminderStatus == "Disabled")
  #expect(diagnostics.habitReminderStatus == "2 scheduled reminders")
}

@Test
func appleSurfaceDiagnosticsReportsSingularSpotlightCounts() {
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 1,
    spotlightIndexedCalendarEventCount: 1,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .disabled,
    widgetSnapshot: nil,
    lastCalendarImportReport: .notStarted,
    importedCalendarEventCount: 0
  )

  #expect(diagnostics.spotlightStatus == "1 task, 1 calendar event")
}

@Test
func appleSurfaceDiagnosticsReportsFailedCalendarImport() {
  let error = LorvexCoreError.unsupportedOperation("Calendar full access denied.")
  let report = CalendarIntegrationReport.failed(operation: "eventkit-import", error: error)
  let diagnostics = AppleSurfaceDiagnostics(
    spotlightIndexedTaskCount: 0,
    spotlightIndexedCalendarEventCount: 0,
    scheduledReminderCount: 0,
    taskReminderScheduleReport: .disabled,
    widgetSnapshot: nil,
    lastCalendarImportReport: report,
    importedCalendarEventCount: 0
  )

  #expect(diagnostics.calendarImportStatus.contains("Failed"))
  #expect(diagnostics.calendarImportStatus.contains("Calendar full access denied"))
}

@MainActor
@Test
func appStoreDiagnosticsProjectsEventKitImportResultsAfterRefresh() async throws {
  let fetched = EventKitFetchedEvent(
    key: "DIAG-001", title: "Diagnostic event", notes: nil,
    startDate: "2026-06-01", startTime: "09:00", endDate: "2026-06-01", endTime: "09:30",
    allDay: false, location: nil, timezone: "UTC")
  let access = FakeEventKitAccess(fetchResult: [fetched])
  let coordinator = EventKitCoordinator(
    access: access, provider: FakeEventKitProvider(),
    loadAccessMode: { .busyOnly }, isEnabled: { true })
  let store = AppStore(
    core: try await makeSeededInMemoryCore(), eventKitCoordinator: coordinator)

  await store.refresh()

  let diag = store.appleSurfaceDiagnostics
  #expect(diag.lastCalendarImportReport.status == .succeeded)
  #expect(diag.importedCalendarEventCount == 1)
  #expect(diag.calendarImportStatus == "1 imported event")
}
