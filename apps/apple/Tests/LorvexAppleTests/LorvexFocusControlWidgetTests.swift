import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetExtension

// MARK: - Widget bundle includes control widget (compile-time check)

/// Verifies that `LorvexFocusControlWidget` is exported from
/// `LorvexWidgetExtension` and is reachable from the test target without
/// conditional imports. The availability guard is `@available(iOS 18.0,
/// macOS 26.0, *)`, so this test runs only on qualifying OS versions.
@available(iOS 18.0, macOS 26.0, *)
@MainActor
@Test
func lorvexFocusControlWidgetIsInstantiable() {
  // Compile-time proof that the type exists and is public.
  let widget = LorvexFocusControlWidget()
  _ = widget
}

@available(iOS 18.0, macOS 26.0, *)
@MainActor
@Test
func lorvexFocusControlWidgetKindMatchesProductMetadata() {
  #expect(LorvexFocusControlWidget.kind == LorvexProductMetadata.controlWidgetKind)
}

// MARK: - Intent

/// Verifies that `OpenLorvexFocusIntent` can be constructed with no arguments
/// (required by AppIntents, which uses a zero-argument `init()`).
@available(iOS 18.0, macOS 26.0, *)
@Test
func openLorvexFocusIntentIsDefaultConstructible() {
  let intent = OpenLorvexFocusIntent()
  _ = intent
}

/// Verifies the iOS 18–25 open mechanism: `openAppWhenRun == true`. This is the
/// deprecated witness for the deployment band that predates `supportedModes`;
/// on iOS 26+ the authoritative declaration is `supportedModes = .foreground`
/// (asserted by `openLorvexFocusIntentDeclaresForegroundSupportedMode`). Tapping
/// the control opens the app on both bands, not run silently in the background.
@available(iOS 18.0, macOS 26.0, *)
@Test
func openLorvexFocusIntentOpensAppWhenRun() {
  #expect(OpenLorvexFocusIntent.openAppWhenRun == true)
}

/// Verifies the iOS 26+ open mechanism: the intent declares `.foreground` in
/// `supportedModes`, the modern replacement for `openAppWhenRun` that brings the
/// app to the foreground from Control Center.
@available(iOS 26.0, macOS 26.0, *)
@Test
func openLorvexFocusIntentDeclaresForegroundSupportedMode() {
  #expect(OpenLorvexFocusIntent.supportedModes.contains(.foreground))
}

/// Verifies that performing the control intent records a Today destination in
/// the handoff store, so a warm resume lands on Today rather than the last tab.
@available(iOS 18.0, macOS 26.0, *)
@Test
func openLorvexFocusIntentStoresTodayDestinationHandoff() async throws {
  let suiteName = "OpenLorvexFocusIntentTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  try await LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    let handoffStore = LorvexIntentHandoffStore()
    handoffStore.clear()

    let intent = OpenLorvexFocusIntent()
    _ = try await intent.perform()

    #expect(handoffStore.consumeDestination() == SidebarSelection.today.rawValue)
  }
}

@available(iOS 18.0, macOS 26.0, *)
@Test
func focusControlValueReflectsSnapshotState() {
  let task = WidgetSnapshot.FocusTask(
    id: "task-control",
    title: "Review control widget",
    status: LorvexTask.Status.open.rawValue,
    dueDate: nil,
    priority: 1,
    listID: nil,
    estimatedMinutes: 25
  )
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-30T12:00:00Z",
    timezone: "America/Los_Angeles",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [task]
  )

  let value = LorvexFocusControlValue.from(
    snapshot: snapshot,
    now: Date(timeIntervalSince1970: 1_780_143_600)
  )

  #expect(value.title == "Review control widget")
  #expect(value.systemImage == "timer")
  #expect(value.availability == .content)
  #expect(value.containsPrivateContent)
}

@available(iOS 18.0, macOS 26.0, *)
@Test
func focusControlValueKeepsInProgressTaskActionable() {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-30T12:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [
      .init(
        id: "started-control",
        title: "Continue started work",
        status: LorvexTask.Status.inProgress.rawValue,
        dueDate: nil,
        priority: 1,
        listID: nil,
        estimatedMinutes: 25
      )
    ]
  )

  #expect(
    LorvexFocusControlValue.from(
      snapshot: snapshot,
      now: Date(timeIntervalSince1970: 1_780_143_600)
    ).title == "Continue started work"
  )
}

@available(iOS 18.0, macOS 26.0, *)
@Test
func focusControlExpiresMaterializedFocusAfterProductTimezoneCrossesMidnight() throws {
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-23T06:30:00Z",
    timezone: "America/Los_Angeles",
    logicalDay: "2026-05-22",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [
      .init(
        id: "yesterday-control",
        title: "Yesterday's focus",
        status: LorvexTask.Status.open.rawValue,
        dueDate: nil,
        priority: 1,
        listID: nil,
        estimatedMinutes: 25
      )
    ]
  )
  // Los Angeles owns this snapshot's logical day. Cross its midnight even
  // though the injected device calendar is already on May 23 in New York.
  let now = try #require(ISO8601DateFormatter().date(from: "2026-05-23T07:45:00Z"))
  var newYork = Calendar(identifier: .gregorian)
  newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

  let value = LorvexFocusControlValue.from(
    snapshot: snapshot,
    now: now,
    calendar: newYork
  )

  #expect(value.title == "Snapshot unavailable")
  #expect(value.systemImage == "exclamationmark.circle")
  #expect(value.availability == .unavailable)
  #expect(!value.containsPrivateContent)
}

@available(iOS 18.0, macOS 26.0, *)
@Test
func focusControlDistinguishesFreshEmptyPlanFromUnavailableSnapshot() {
  let now = Date(timeIntervalSince1970: 1_780_142_400)
  let empty = WidgetSnapshot(
    generatedAt: "2026-05-30T12:00:00Z",
    timezone: "UTC",
    logicalDay: "2026-05-30",
    stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: [])

  let emptyValue = LorvexFocusControlValue.from(snapshot: empty, now: now)
  let unavailableValue = LorvexFocusControlValue.from(
    result: .fallback(.init(reason: .invalidJSON, detail: "test")),
    now: now)

  #expect(emptyValue.title == "No focus")
  #expect(emptyValue.systemImage == "scope")
  #expect(emptyValue.availability == .empty)
  #expect(!emptyValue.containsPrivateContent)
  #expect(unavailableValue.title == "Snapshot unavailable")
  #expect(unavailableValue.systemImage == "exclamationmark.circle")
  #expect(unavailableValue.availability == .unavailable)
  #expect(!unavailableValue.containsPrivateContent)
}

@available(iOS 18.0, macOS 26.0, *)
@Test
func focusControlPreviewUsesLocalizedSeed() {
  #expect(LorvexFocusControlValue.preview.title == "Review spec")
  #expect(LorvexFocusControlValue.preview.systemImage == "timer")
}

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
