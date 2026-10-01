import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWatch

// MARK: - LorvexWatchComplicationEntryMapper tests

@Suite("LorvexWatchComplicationEntryMapper")
struct LorvexWatchComplicationTests {

  /// 2026-05-24T10:00:00Z.
  private let now = Date(timeIntervalSince1970: 1_779_616_800)

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
  }

  private func makeSnapshot(tasks: [WidgetSnapshot.TodayTask]) -> WidgetSnapshot {
    WidgetSnapshot(
      generatedAt: "2026-05-24T10:00:00Z",
      timezone: "UTC",
      // Like the projector: the tasks left, not the finished ones.
      stats: .init(
        todayCount: tasks.filter(\.isActionable).count, overdueCount: 0,
        dueTodayCount: tasks.count),
      briefing: nil,
      tasks: tasks
    )
  }

  private func entry(tasks: [WidgetSnapshot.TodayTask]) -> LorvexWatchComplicationEntry {
    LorvexWatchComplicationEntryMapper.entry(
      from: .snapshot(makeSnapshot(tasks: tasks)), at: now, calendar: utc)
  }

  private func task(
    id: String, title: String, status: LorvexTask.Status = .open, priority: Int? = nil,
    estimatedMinutes: Int? = nil, start: String? = nil, end: String? = nil
  ) -> WidgetSnapshot.TodayTask {
    .init(
      id: id,
      title: title,
      status: status.rawValue,
      dueDate: nil,
      priority: priority,
      listID: nil,
      estimatedMinutes: estimatedMinutes,
      scheduledStart: start,
      scheduledEnd: end
    )
  }

  // MARK: - Tests

  @Test("a single open task is listed, but does not lead without a time or a start")
  func entryFromSingleOpenTask() {
    let entry = entry(tasks: [task(id: "t1", title: "Ship v1")])

    #expect(entry.date == now)
    #expect(entry.model.state == .content)
    #expect(entry.model.lead == nil)
    #expect(entry.model.taskRows.map(\.title) == ["Ship v1"])
    #expect(entry.model.dayLine == "1 left today")
    #expect(entry.model.remainingCount == 1)
    #expect(entry.model.circularContent == .remaining(1))
    #expect(entry.isPlaceholder == false)
  }

  @Test("a started task leads and says it is started")
  func entryFromInProgressTask() {
    // The phone sends Today's order, where started tasks come first.
    let entry = entry(tasks: [
      task(
        id: "started", title: "Continue shipping", status: .inProgress, priority: 3,
        estimatedMinutes: 30),
      task(id: "open", title: "Not yet", priority: 1),
    ])

    #expect(entry.model.lead?.title == "Continue shipping")
    #expect(entry.model.lead?.line == "Started · about 30 min")
    #expect(entry.model.lead?.shortLine == "Started")
    #expect(entry.model.taskRows.map(\.title) == ["Not yet"])
  }

  @Test("a running time leads with its minutes left")
  func entryFromRunningTime() {
    let entry = entry(tasks: [
      task(id: "first", title: "First in the list"),
      task(id: "running", title: "Deep work", start: "09:40", end: "10:25"),
    ])

    #expect(entry.model.lead?.title == "Deep work")
    #expect(entry.model.lead?.isRunning == true)
    #expect(entry.model.circularContent == .running(minutesLeft: 25))
    #expect(entry.model.taskRows.map(\.title) == ["First in the list"])
  }

  @Test("widget kind matches shared product metadata")
  @MainActor
  func widgetKindMatchesProductMetadata() {
    #expect(LorvexWatchComplicationWidget.kind == LorvexProductMetadata.watchComplicationKind)
  }

  @Test("placeholder entry has the sample day's shape and redacts")
  func placeholderEntryUsesSampleDay() {
    let entry = LorvexWatchComplicationProvider.placeholderEntry(at: now)

    #expect(entry.date == now)
    #expect(entry.model.state == .content)
    #expect(entry.model.lead?.title == "Review spec")
    #expect(entry.isPlaceholder == true)
  }

  @Test("gallery snapshot uses representative unredacted content")
  func gallerySnapshotUsesRepresentativeContent() {
    let provider = LorvexWatchComplicationProvider(appGroupID: "group.invalid.preview-test")
    let entry = provider.makeSnapshotEntry(isPreview: true, at: now)

    #expect(entry.date == now)
    #expect(entry.model.lead?.title == "Review spec")
    #expect(entry.model.state == .content)
    #expect(entry.isPlaceholder == false)
  }

  @Test("timeline cadence follows shared freshness policy instead of fixed polling")
  func timelineCadenceUsesSharedPolicy() {
    let fresh = LorvexWatchComplicationEntryMapper.timeline(
      from: .snapshot(makeSnapshot(tasks: [task(id: "fresh", title: "Fresh task")])),
      at: now,
      calendar: utc
    )
    let fallback = LorvexWatchComplicationEntryMapper.timeline(
      from: .fallback(.init(reason: .missingFile, detail: "test")),
      at: now,
      calendar: utc
    )

    #expect(fresh.entries.map(\.date) == [now])
    #expect(fresh.refreshAfter == now.addingTimeInterval(2 * 60 * 60))
    #expect(
      fallback.refreshAfter
        == WidgetTimelineRefreshPolicy().nextLocalMidnight(after: now, calendar: utc)
    )
    #expect(fallback.refreshAfter > now.addingTimeInterval(15 * 60))
  }

  @Test("a saved time later today adds an entry where the lead changes")
  func timelineAddsEntriesAtTimeChanges() throws {
    let timeline = LorvexWatchComplicationEntryMapper.timeline(
      from: .snapshot(makeSnapshot(tasks: [
        task(id: "first", title: "First in the list"),
        task(id: "later", title: "Call at half past", start: "10:30", end: "11:00"),
      ])),
      at: now,
      calendar: utc
    )
    let halfPast = now.addingTimeInterval(30 * 60)

    #expect(timeline.entries.first?.model.lead?.title == "Call at half past", "the next time leads")
    #expect(timeline.entries.first?.model.lead?.isRunning == false)
    let atStart = try #require(timeline.entries.first { $0.date == halfPast })
    #expect(atStart.model.lead?.title == "Call at half past")
    #expect(atStart.model.lead?.isRunning == true)
  }

  @Test("entry from fallback is unavailable, not empty")
  func entryFromFallback() {
    let result = WidgetSnapshotLoadResult.fallback(.init(reason: .missingFile, detail: "test"))
    let entry = LorvexWatchComplicationEntryMapper.entry(from: result, at: now)

    #expect(entry.model.state == .fallback)
    #expect(entry.model.lead == nil)
    #expect(entry.model.statusText == "Open Lorvex to sync")
    #expect(entry.model.circularContent == .unavailable)
    #expect(entry.isPlaceholder == false)
  }

  @Test("entry with several tasks leads with the started one and counts the rest")
  func entryFromMultipleTasks() {
    let entry = entry(tasks: [
      task(id: "t1", title: "Task A", status: .inProgress),
      task(id: "t2", title: "Task B"),
    ])

    #expect(entry.model.lead?.title == "Task A")
    #expect(entry.model.upcomingCount == 1)
    #expect(entry.model.taskRows.map(\.title) == ["Task B"])
    #expect(entry.model.circularContent == .remaining(2))
  }

  @Test("entry from a snapshot with only finished tasks is empty")
  func entryFromCompletedTasksOnly() {
    let entry = entry(tasks: [task(id: "c1", title: "Done", status: .completed)])

    #expect(entry.model.state == .empty)
    #expect(entry.model.lead == nil)
    #expect(entry.model.circularContent == .empty)
  }

  // MARK: - Relevance

  @Test("relevance scales with the tasks left today")
  func relevanceScalesWithTasksLeft() {
    let entry = entry(tasks: [task(id: "t1", title: "Deep work")])

    #expect(entry.relevance != nil)
    #expect(entry.relevance?.duration != nil)
  }

  @Test("relevance is nil when nothing is left today")
  func relevanceNilWhenNothingIsLeft() {
    #expect(entry(tasks: []).relevance == nil)
  }
}
