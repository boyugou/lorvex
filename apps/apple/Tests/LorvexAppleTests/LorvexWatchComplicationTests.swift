import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

// MARK: - LorvexWatchComplicationEntryMapper tests

@Suite("LorvexWatchComplicationEntryMapper")
struct LorvexWatchComplicationTests {

  private let now = Date(timeIntervalSince1970: 1_779_616_800)

  private func makeSnapshotResult(tasks: [WidgetSnapshot.FocusTask]) -> WidgetSnapshotLoadResult {
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T10:00:00Z",
      timezone: "UTC",
      stats: .init(
        focusCount: tasks.count, overdueCount: 0, dueTodayCount: tasks.count),
      briefing: nil,
      focusTasks: tasks
    )
    return .snapshot(snapshot)
  }

  private func openTask(id: String, title: String, priority: Int? = nil) -> WidgetSnapshot.FocusTask
  {
    .init(
      id: id,
      title: title,
      status: "open",
      dueDate: nil,
      priority: priority,
      listID: nil,
      estimatedMinutes: nil
    )
  }

  // MARK: - Tests

  @Test("entry has correct title and status for single open task")
  func entryFromSingleOpenTask() {
    let result = makeSnapshotResult(tasks: [openTask(id: "t1", title: "Ship v1")])
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.taskTitle == "Ship v1")
    #expect(entry.statusText == "1 focus task")
    #expect(entry.date == now)
    #expect(entry.availability == .content)
  }

  @Test("entry keeps an in-progress task as the primary focus")
  func entryFromInProgressTask() {
    let startedTask = WidgetSnapshot.FocusTask(
      id: "started",
      title: "Continue shipping",
      status: "in_progress",
      dueDate: nil,
      priority: 1,
      listID: nil,
      estimatedMinutes: 30
    )

    let entry = LorvexWatchComplicationEntryMapper.entry(
      from: makeSnapshotResult(tasks: [startedTask]),
      at: now
    )

    #expect(entry.taskTitle == "Continue shipping")
    #expect(entry.openFocusCount == 1)
  }

  @Test("widget kind matches shared product metadata")
  @MainActor
  func widgetKindMatchesProductMetadata() {
    #expect(LorvexWatchComplicationWidget.kind == LorvexProductMetadata.watchComplicationKind)
  }

  @Test("placeholder entry uses localized watch catalog strings")
  func placeholderEntryUsesLocalizedStrings() {
    let entry = LorvexWatchComplicationProvider.placeholderEntry(at: now)

    #expect(entry.date == now)
    #expect(entry.taskTitle == "Review pull request")
    #expect(entry.statusText == "1 focus task")
    #expect(entry.openFocusCount == 1)
    #expect(entry.primaryPriorityTier == 1)
    #expect(entry.availability == .content)
    #expect(entry.isPlaceholder == true)
  }

  @Test("gallery snapshot uses representative unredacted content")
  func gallerySnapshotUsesRepresentativeContent() {
    let provider = LorvexWatchComplicationProvider(appGroupID: "group.invalid.preview-test")
    let entry = provider.makeSnapshotEntry(isPreview: true, at: now)

    #expect(entry.date == now)
    #expect(entry.taskTitle == "Review spec")
    #expect(entry.openFocusCount == 1)
    #expect(entry.availability == .content)
    #expect(entry.isPlaceholder == false)
  }

  @Test("timeline cadence follows shared freshness policy instead of fixed polling")
  func timelineCadenceUsesSharedPolicy() throws {
    let provider = LorvexWatchComplicationProvider()
    let date = try #require(
      ISO8601DateFormatter().date(from: "2026-05-24T10:00:00Z")
    )
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-24T10:00:00Z",
      timezone: "UTC",
      stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
      briefing: nil,
      focusTasks: [openTask(id: "fresh", title: "Fresh task")]
    )

    let fresh = provider.makeTimelineResult(
      from: .snapshot(snapshot),
      at: date,
      calendar: utc
    )
    let fallback = provider.makeTimelineResult(
      from: .fallback(.init(reason: .missingFile, detail: "test")),
      at: date,
      calendar: utc
    )

    #expect(fresh.refreshAfter == date.addingTimeInterval(2 * 60 * 60))
    #expect(
      fallback.refreshAfter
        == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: date, calendar: utc)
    )
    #expect(fallback.refreshAfter > date.addingTimeInterval(15 * 60))
  }

  @Test("entry carries the primary task's priority tier")
  func entryCarriesPriority() {
    let result = makeSnapshotResult(
      tasks: [openTask(id: "t1", title: "Ship v1", priority: 2)])
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.primaryPriorityTier == 2)
    #expect(entry.isPlaceholder == false)
  }

  @Test("entry from fallback has no priority tier and is not a placeholder")
  func entryFromFallbackHasNoPriorityAndIsNotPlaceholder() {
    let result = WidgetSnapshotLoadResult.fallback(.init(reason: .missingFile, detail: "test"))
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.primaryPriorityTier == nil)
    #expect(entry.availability == .unavailable)
    #expect(entry.isPlaceholder == false)
  }

  @Test("entry has correct status text for multiple open tasks")
  func entryFromMultipleTasks() {
    let result = makeSnapshotResult(tasks: [
      openTask(id: "t1", title: "Task A"),
      openTask(id: "t2", title: "Task B"),
    ])
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.taskTitle == "Task A")
    #expect(entry.statusText == "2 tasks")
  }

  @Test("entry from fallback result is unavailable, not empty")
  func entryFromFallback() {
    let result = WidgetSnapshotLoadResult.fallback(
      .init(reason: .missingFile, detail: "test")
    )
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.taskTitle == nil)
    #expect(entry.statusText == "Snapshot unavailable")
    #expect(entry.availability == .unavailable)
  }

  @Test("entry from snapshot with only completed tasks has nil title")
  func entryFromCompletedTasksOnly() {
    let completedTask = WidgetSnapshot.FocusTask(
      id: "c1",
      title: "Done",
      status: "completed",
      dueDate: nil,
      priority: nil,
      listID: nil,
      estimatedMinutes: nil
    )
    let result = makeSnapshotResult(tasks: [completedTask])
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.taskTitle == nil)
    #expect(entry.statusText == "No focus")
    #expect(entry.availability == .empty)
  }

  @Test("circular complication shows remaining count without global progress math")
  func circularComplicationUsesRemainingCountOnly() {
    let content = LorvexWatchComplicationEntry(
      date: now,
      taskTitle: "Deep work",
      statusText: "3 tasks",
      openFocusCount: 3,
      availability: .content)
    let empty = LorvexWatchComplicationEntry(
      date: now,
      taskTitle: nil,
      statusText: "No focus",
      openFocusCount: 0,
      availability: .empty)
    let unavailable = LorvexWatchComplicationEntry(
      date: now,
      taskTitle: nil,
      statusText: "Snapshot unavailable",
      openFocusCount: 0,
      availability: .unavailable)

    #expect(LorvexWatchComplicationView.circularContent(for: content) == .remaining(3))
    #expect(LorvexWatchComplicationView.circularContent(for: empty) == .empty)
    #expect(LorvexWatchComplicationView.circularContent(for: unavailable) == .unavailable)
  }

  // MARK: - Relevance

  @Test("relevance scales with the open focus task count")
  func relevanceScalesWithOpenFocusCount() {
    let entry = LorvexWatchComplicationEntry(
      date: now,
      taskTitle: "Deep work",
      statusText: "1 focus task",
      openFocusCount: 1
    )

    #expect(entry.relevance != nil)
    #expect(entry.relevance?.duration != nil)
  }

  @Test("relevance is nil when there are no open focus tasks")
  func relevanceNilWithoutOpenFocusTasks() {
    let entry = LorvexWatchComplicationEntry(
      date: now,
      taskTitle: nil,
      statusText: "No focus",
      openFocusCount: 0
    )

    #expect(entry.relevance == nil)
  }
}
