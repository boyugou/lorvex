import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetExtension

@Suite("Today widget configuration")
struct TodayWidgetConfigurationTests {
  @Test("configuration intent defaults to every list")
  func configurationDefaultsToEveryList() {
    let intent = LorvexTodayWidgetConfigurationIntent()

    #expect(intent.list == nil)
  }

  @Test("widget list entities default to identifier fallback")
  func widgetListEntityQueryDefaultsToIdentifierFallback() async throws {
    let entities = try await LorvexWidgetListEntityQuery().entities(for: [
      LorvexPreviewSeedID.appleNativeList
    ])

    #expect(entities == [LorvexWidgetListEntity(id: LorvexPreviewSeedID.appleNativeList)])
  }

  private static let work = WidgetSnapshot.TodayTask(
    id: "work-task", title: "Work", status: "open", dueDate: nil,
    priority: 1, listID: "work", estimatedMinutes: nil)
  private static let home = WidgetSnapshot.TodayTask(
    id: "home-task", title: "Home", status: "open", dueDate: nil,
    priority: 2, listID: "home", estimatedMinutes: nil)
  private static let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-30T12:00:00Z",
    timezone: "UTC",
    stats: .init(todayCount: 2, overdueCount: 1, dueTodayCount: 1),
    briefing: "Do Work, then Home.",
    tasks: [work, home],
    listStats: [
      .init(id: "work", stats: .init(todayCount: 1, overdueCount: 0, dueTodayCount: 1))
    ])

  @Test("list scoping keeps the list's tasks and counts and drops the day's briefing")
  func listScopingClearsGlobalBriefing() {
    let scoped = Self.snapshot.scoped(toList: "work")

    #expect(scoped.tasks.map(\.id) == ["work-task"])
    #expect(scoped.stats.todayCount == 1)
    #expect(scoped.stats.dueTodayCount == 1)
    #expect(scoped.briefing == nil, "the briefing speaks about the whole day, hidden tasks included")
    #expect(Self.snapshot.scoped(toList: nil) == Self.snapshot)
  }

  @Test("a list without stored counts falls back to counting its tasks")
  func listScopingCountsTasksWithoutStoredStats() {
    let scoped = Self.snapshot.scoped(toList: "home")

    #expect(scoped.tasks.map(\.id) == ["home-task"])
    #expect(scoped.stats.todayCount == 1)
    #expect(scoped.stats.overdueCount == 0)
  }
}
