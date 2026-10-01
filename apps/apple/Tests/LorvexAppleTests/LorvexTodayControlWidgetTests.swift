import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetExtension

// MARK: - Control widget

@MainActor
@Test
func lorvexTodayControlWidgetIsInstantiable() {
  // Compile-time proof that the type exists and is public.
  let widget = LorvexTodayControlWidget()
  _ = widget
}

@MainActor
@Test
func lorvexTodayControlWidgetKindMatchesProductMetadata() {
  #expect(LorvexTodayControlWidget.kind == LorvexProductMetadata.controlWidgetKind)
}

// MARK: - Intent

/// AppIntents constructs the control's intent through a zero-argument `init()`.
@Test
func openLorvexTodayIntentIsDefaultConstructible() {
  let intent = OpenLorvexTodayIntent()
  _ = intent
}

/// Tapping the control opens the app rather than running silently in the
/// background.
@Test
func openLorvexTodayIntentOpensTheApp() {
  #expect(OpenLorvexTodayIntent.openAppWhenRun == true)
  #expect(OpenLorvexTodayIntent.supportedModes.contains(.foreground))
}

/// Performing the control intent records a Today destination in the handoff
/// store, so a warm resume lands on Today rather than the last tab.
@Test
func openLorvexTodayIntentStoresTodayDestinationHandoff() async throws {
  let suiteName = "OpenLorvexTodayIntentTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  try await LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    let handoffStore = LorvexIntentHandoffStore()
    handoffStore.clear()

    let intent = OpenLorvexTodayIntent()
    _ = try await intent.perform()

    #expect(handoffStore.consumeDestination() == SidebarSelection.today.rawValue)
  }
}

// MARK: - Value

/// A snapshot of `tasks` for 2026-05-30 in `timezone`.
private func controlSnapshot(
  _ tasks: [WidgetSnapshot.TodayTask], timezone: String = "UTC",
  logicalDay: String = "2026-05-30", generatedAt: String = "2026-05-30T12:00:00Z"
) -> WidgetSnapshot {
  WidgetSnapshot(
    generatedAt: generatedAt,
    timezone: timezone,
    logicalDay: logicalDay,
    stats: .init(todayCount: tasks.count, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    tasks: tasks)
}

private func controlTask(
  id: String, title: String, status: LorvexTask.Status = .open, priority: Int? = 1,
  scheduledStart: String? = nil, scheduledEnd: String? = nil
) -> WidgetSnapshot.TodayTask {
  WidgetSnapshot.TodayTask(
    id: id, title: title, status: status.rawValue, dueDate: nil, priority: priority,
    listID: nil, estimatedMinutes: 25, scheduledStart: scheduledStart,
    scheduledEnd: scheduledEnd)
}

/// 2026-05-30T12:20:00Z.
private let controlNow = Date(timeIntervalSince1970: 1_780_143_600)

@Test
func todayControlValueCountsTheTasksWhenNoneLeads() {
  let value = LorvexTodayControlValue.from(
    snapshot: controlSnapshot([
      controlTask(id: "first", title: "Review control widget", priority: 1),
      controlTask(id: "second", title: "Second task", priority: 2),
    ]),
    now: controlNow)

  #expect(value.title == "2 left today", "an untimed, unstarted task is not presented as now")
  #expect(value.systemImage == "list.bullet")
  #expect(value.availability == .content)
  #expect(value.containsPrivateContent)
}

@Test
func todayControlValueNamesTheTaskWhoseTimeIsRunning() {
  // At 12:20 UTC the second task's time (12:00–13:00) contains the clock, so
  // it leads although the first task sorts above it.
  let value = LorvexTodayControlValue.from(
    snapshot: controlSnapshot([
      controlTask(id: "first", title: "Untimed task", priority: 1),
      controlTask(
        id: "timed", title: "Timed task", priority: 2, scheduledStart: "12:00",
        scheduledEnd: "13:00"),
    ]),
    now: controlNow)

  #expect(value.title == "Timed task")
}

@Test
func todayControlValueNamesAStartedTask() {
  let value = LorvexTodayControlValue.from(
    snapshot: controlSnapshot([
      controlTask(id: "started", title: "Continue started work", status: .inProgress)
    ]),
    now: controlNow)

  #expect(value.title == "Continue started work")
  #expect(value.availability == .content)
}

@Test
func todayControlExpiresTheSnapshotAfterProductTimezoneCrossesMidnight() throws {
  let snapshot = controlSnapshot(
    [controlTask(id: "yesterday", title: "Yesterday's task")],
    timezone: "America/Los_Angeles", logicalDay: "2026-05-22",
    generatedAt: "2026-05-23T06:30:00Z")
  // Los Angeles owns this snapshot's logical day. Cross its midnight even
  // though the injected device calendar is already on May 23 in New York.
  let now = try #require(ISO8601DateFormatter().date(from: "2026-05-23T07:45:00Z"))
  var newYork = Calendar(identifier: .gregorian)
  newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

  let value = LorvexTodayControlValue.from(snapshot: snapshot, now: now, calendar: newYork)

  #expect(value.title == "Snapshot unavailable")
  #expect(value.systemImage == "exclamationmark.circle")
  #expect(value.availability == .unavailable)
  #expect(!value.containsPrivateContent)
}

@Test
func todayControlDistinguishesAnEmptyDayFromAnUnavailableSnapshot() {
  let emptyValue = LorvexTodayControlValue.from(snapshot: controlSnapshot([]), now: controlNow)
  let unavailableValue = LorvexTodayControlValue.from(
    result: .fallback(.init(reason: .invalidJSON, detail: "test")),
    now: controlNow)

  #expect(emptyValue.title == "All clear")
  #expect(emptyValue.systemImage == "checkmark.circle")
  #expect(emptyValue.availability == .empty)
  #expect(!emptyValue.containsPrivateContent)
  #expect(unavailableValue.title == "Snapshot unavailable")
  #expect(unavailableValue.systemImage == "exclamationmark.circle")
  #expect(unavailableValue.availability == .unavailable)
  #expect(!unavailableValue.containsPrivateContent)
}

@Test
func todayControlPreviewUsesLocalizedSeed() {
  #expect(LorvexTodayControlValue.preview.title == "Review spec")
  #expect(LorvexTodayControlValue.preview.systemImage == "circle")
}

// MARK: - Interactive widget intents

@Test
func widgetCompleteTaskIntentCarriesTaskTitleForSystemDisplay() {
  let intent = WidgetCompleteTaskIntent(taskID: "task-widget-title", title: "Review native widget")

  #expect(intent.task.id == "task-widget-title")
  #expect(intent.task.title == "Review native widget")
  #expect(WidgetCompleteTaskIntent.openAppWhenRun == false)
}

@Test
func widgetCompleteHabitIntentCarriesHabitForSystemDisplay() {
  let intent = WidgetCompleteHabitIntent(habitID: "habit-widget", name: "Meditate")

  #expect(intent.habitID == "habit-widget")
  #expect(intent.habitName == "Meditate")
  #expect(WidgetCompleteHabitIntent.openAppWhenRun == false)
}

@Test
func widgetDeferTaskIntentCarriesTaskTitleForSystemDisplay() {
  let intent = WidgetDeferTaskIntent(taskID: "task-widget-defer", title: "Plan native widget")

  #expect(intent.task.id == "task-widget-defer")
  #expect(intent.task.title == "Plan native widget")
  #expect(WidgetDeferTaskIntent.openAppWhenRun == false)
}

@Test
func widgetTaskEntityDefaultsDisplayToIdentifierWhenTitleIsMissing() {
  let entity = WidgetTaskEntity(id: "task-only-id")

  #expect(entity.id == "task-only-id")
  #expect(entity.title.isEmpty)
}

@Test
func widgetTaskEntityQueryReturnsIdentifierBackedEntities() async throws {
  let entities = try await WidgetTaskEntityQuery().entities(for: ["task-a", "task-b"])

  #expect(entities.map(\.id) == ["task-a", "task-b"])
  #expect(entities.allSatisfy { $0.title.isEmpty })
}
