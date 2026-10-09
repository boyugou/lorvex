import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexSystemIntents
@testable import LorvexWidgetViews

/// How a habit set aside for today reaches the surfaces that read the shared
/// snapshot (widgets, the watch) and the Siri and Shortcuts entity.
@Suite("Habit skip on the snapshot surfaces")
struct HabitSkipSurfacesTests {
  private func summary(
    _ id: String, done: Int = 0, target: Int = 1, skipped: Bool = false
  ) -> WidgetSnapshot.HabitSummary {
    WidgetSnapshot.HabitSummary(
      id: id, name: id, icon: nil, completedToday: done, target: target, isSkipped: skipped)
  }

  private func habit(isSkipped: Bool) -> LorvexHabit {
    LorvexHabit(
      id: "habit-1", name: "Cardio", icon: nil, color: nil, cue: nil, frequencyType: "daily",
      targetCount: 1, completionsToday: 0, totalCompletions: 0, completionRate30d: 0,
      archived: false, isSkipped: isSkipped)
  }

  // MARK: Snapshot

  @Test("The skipped flag round-trips through the snapshot JSON under is_skipped")
  func skippedFlagRoundTrips() throws {
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-05-25T08:00:00Z", timezone: "UTC",
      stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0), briefing: nil, tasks: [],
      habits: [summary("a", skipped: true), summary("b")])
    let data = try JSONEncoder().encode(snapshot)
    #expect(String(decoding: data, as: UTF8.self).contains("\"is_skipped\":true"))
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    #expect(decoded.habits.map(\.isSkipped) == [true, false])
  }

  @Test("A snapshot written without the flag decodes every habit as not skipped")
  func legacyHabitDecodesAsNotSkipped() throws {
    let json = Data(
      """
      {"id":"h1","name":"Run","completed_today":0,"target":1}
      """.utf8)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.HabitSummary.self, from: json)
    #expect(decoded.isSkipped == false)
    #expect(decoded.name == "Run")
    #expect(decoded.icon == nil)
    #expect(decoded.color == nil)
  }

  @Test("A habit is open only while it is neither met nor set aside")
  func openTodayExcludesDoneAndSkipped() {
    #expect(summary("open").isOpenToday)
    #expect(summary("part", done: 1, target: 3).isOpenToday)
    #expect(!summary("done", done: 1).isOpenToday)
    #expect(!summary("skipped", skipped: true).isOpenToday)
  }

  @Test("The projector carries a skipped habit into the snapshot")
  func projectorCarriesTheSkip() {
    let now = Date(timeIntervalSince1970: 1_779_465_600)
    let today = TodaySnapshot(summary: "", tasks: [], localChangeSequence: 0)
    let snapshot = WidgetSnapshotProjector(now: { now }).snapshot(
      logicalDay: "2026-05-22", today: today, timezone: "UTC",
      habitCatalog: HabitCatalogSnapshot(habits: [habit(isSkipped: true)]))
    #expect(snapshot.habits.map(\.id) == ["habit-1"])
    #expect(snapshot.habits.first?.isSkipped == true)
    #expect(snapshot.habits.first?.completedToday == 0)
  }

  // MARK: Widget layout

  @Test("The count leaves a skipped habit out of both the done and the total")
  func progressLeavesOutSkippedHabits() {
    let habits = [
      summary("done", done: 1), summary("open"), summary("skipped", skipped: true),
    ]
    let progress = HabitsWidgetLayout.progress(habits)
    #expect(progress.done == 1)
    #expect(progress.total == 2)

    let onlySkipped = HabitsWidgetLayout.progress([summary("skipped", skipped: true)])
    #expect(onlySkipped.done == 0)
    #expect(onlySkipped.total == 0)
    #expect(HabitsWidgetLayout.progress([]).total == 0)
  }

  @Test("When tiles run short, a skipped habit gives way to the habits still open")
  func overflowKeepsOpenHabitsInView() {
    let habits = [
      summary("skipped", skipped: true), summary("done", done: 1), summary("open-1"),
      summary("open-2"), summary("open-3"),
    ]
    let tiles = HabitsWidgetLayout.tiles(habits, capacity: 4)
    #expect(
      tiles == [
        .habit(summary("open-1")), .habit(summary("open-2")), .habit(summary("open-3")),
        .more(2),
      ])

    // With room for every habit they keep their order, skipped one included.
    let all = HabitsWidgetLayout.tiles(habits, capacity: 8)
    #expect(all.count == 5)
    #expect(all.first == .habit(summary("skipped", skipped: true)))
  }

  // MARK: Siri and Shortcuts

  @Test("The entity carries the skip from its habit")
  func entityCarriesTheSkip() {
    #expect(LorvexHabitEntity(habit: habit(isSkipped: true)).isSkipped)
    #expect(!LorvexHabitEntity(habit: habit(isSkipped: false)).isSkipped)
    #expect(
      !LorvexHabitEntity(id: "h", name: "Cardio", completionsToday: 0, targetCount: 1).isSkipped)
  }
}
