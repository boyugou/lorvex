import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetExtension

@Suite("Today widget configuration")
struct TodayWidgetConfigurationTests {
  @Test("configuration intent defaults to the Today task view")
  func configurationDefaultsToTodayView() {
    let intent = LorvexTodayWidgetConfigurationIntent()

    #expect(intent.viewMode == .today)
    #expect(intent.list == nil)
  }

  @Test("snapshot entry carries configured Today widget view mode")
  func snapshotEntryCarriesConfiguredViewMode() {
    let entry = LorvexSnapshotEntry(
      date: Date(timeIntervalSince1970: 0),
      snapshot: nil,
      statusText: "Open Lorvex to refresh",
      todayWidgetViewMode: .focus,
      todayWidgetListID: LorvexPreviewSeedID.appleNativeList
    )

    #expect(entry.todayWidgetViewMode == .focus)
    #expect(entry.todayWidgetListID == LorvexPreviewSeedID.appleNativeList)
  }

  @Test("widget list entities default to identifier fallback")
  func widgetListEntityQueryDefaultsToIdentifierFallback() async throws {
    let entities = try await LorvexWidgetListEntityQuery().entities(for: [
      LorvexPreviewSeedID.appleNativeList
    ])

    #expect(entities == [LorvexWidgetListEntity(id: LorvexPreviewSeedID.appleNativeList)])
  }

  @Test("list filtering removes a global briefing that can describe hidden tasks")
  func listFilteringClearsGlobalBriefing() {
    let work = WidgetSnapshot.FocusTask(
      id: "work-task", title: "Work", status: "open", dueDate: nil,
      priority: 1, listID: "work", estimatedMinutes: nil)
    let home = WidgetSnapshot.FocusTask(
      id: "home-task", title: "Home", status: "open", dueDate: nil,
      priority: 2, listID: "home", estimatedMinutes: nil)
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-30T12:00:00Z",
      timezone: "UTC",
      stats: .init(focusCount: 2, overdueCount: 1, dueTodayCount: 1),
      briefing: "Do Work, then Home.",
      focusTasks: [work, home],
      todayTasks: [
        .init(
          id: work.id, title: work.title, dueDate: nil, priority: work.priority,
          estimatedMinutes: nil, listID: work.listID),
        .init(
          id: home.id, title: home.title, dueDate: nil, priority: home.priority,
          estimatedMinutes: nil, listID: home.listID),
      ],
      listStats: [
        .init(
          id: "work",
          stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1))
      ])

    let filtered = TodayWidgetSnapshotFilter.applying(listID: "work", to: snapshot)

    #expect(filtered.focusTasks.map(\.id) == ["work-task"])
    #expect(filtered.todayTasks.map(\.id) == ["work-task"])
    #expect(filtered.stats.focusCount == 1)
    #expect(filtered.briefing == nil)
    #expect(TodayWidgetSnapshotFilter.applying(listID: nil, to: snapshot) == snapshot)
  }
}
