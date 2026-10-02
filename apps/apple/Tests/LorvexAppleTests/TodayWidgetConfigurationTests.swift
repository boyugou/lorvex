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
    lists: [.init(id: "work", name: "Work", icon: nil), .init(id: "home", name: "Home", icon: nil)],
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
    #expect(scoped.scopeList?.name == "Work")
    #expect(Self.snapshot.scoped(toList: nil) == Self.snapshot)
  }

  @Test("a widget configured with a list is titled with the list's name")
  func listScopedWidgetIsTitledWithTheList() {
    func headline(_ snapshot: WidgetSnapshot, _ family: WidgetFamilyKind) -> String {
      let now = Date(timeIntervalSince1970: 1_780_142_400)  // 2026-05-30T12:00:00Z
      return WidgetRenderModelBuilder().model(
        entry: WidgetTimelineEntry(
          date: now, state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
          refreshAfter: now.addingTimeInterval(1800)),
        family: family, statusText: "Updated now"
      ).headline
    }
    #expect(headline(Self.snapshot.scoped(toList: "work"), .systemMedium) == "Work")
    #expect(headline(Self.snapshot.scoped(toList: "work"), .systemSmall) == "Work")
    #expect(headline(Self.snapshot, .systemMedium) == "Today")
    // A list no longer in the snapshot leaves the widget titled "Today".
    #expect(headline(Self.snapshot.scoped(toList: "gone"), .systemMedium) == "Today")
  }

  @Test("a list without stored counts falls back to counting its tasks")
  func listScopingCountsTasksWithoutStoredStats() {
    let scoped = Self.snapshot.scoped(toList: "home")

    #expect(scoped.tasks.map(\.id) == ["home-task"])
    #expect(scoped.stats.todayCount == 1)
    #expect(scoped.stats.overdueCount == 0)
  }
}
