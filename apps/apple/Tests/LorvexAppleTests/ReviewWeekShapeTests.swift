import Foundation
import LorvexCore
import Testing

/// The week review's finished count per day: seven logical days ending on the
/// review's last day, counted in the logical time zone.
@Suite("Review week shape")
struct ReviewWeekShapeTests {
  private let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

  @Test("Seven days oldest first, counting each completion on its logical day")
  func countsByDay() {
    let shape = LorvexWeekShape.build(
      endKey: "2026-10-01",
      completedAt: [
        "2026-09-25T14:00:00Z",
        "2026-09-25T15:30:00.123Z",
        "2026-10-01T12:00:00Z",
      ],
      timeZone: newYork)
    #expect(shape.days.map(\.key) == [
      "2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01",
    ])
    #expect(shape.days.map(\.finished) == [2, 0, 0, 0, 0, 0, 1])
    #expect(shape.peak == 2)
  }

  @Test("A late-evening completion counts on the local day, not the UTC day")
  func logicalTimeZone() {
    // 01:30 UTC on Oct 1 is 21:30 on Sep 30 in New York.
    let shape = LorvexWeekShape.build(
      endKey: "2026-10-01", completedAt: ["2026-10-01T01:30:00Z"], timeZone: newYork)
    #expect(shape.days.map(\.finished) == [0, 0, 0, 0, 0, 1, 0])
  }

  @Test("Completions outside the week and unreadable stamps are ignored")
  func ignoresOutside() {
    let shape = LorvexWeekShape.build(
      endKey: "2026-10-01",
      completedAt: ["2026-09-24T16:00:00Z", "2026-10-02T16:00:00Z", "not a date"],
      timeZone: newYork)
    #expect(shape.peak == 0)
    #expect(shape.days.count == 7)
  }

  @Test("Loading reads the week's completed tasks from the core")
  @MainActor
  func loadsFromCore() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let today = try await core.loadToday()
    let todayKey = try #require(today.logicalDay)
    let task = try await core.createTask(TaskCreateDraft(title: "Ship it"))
    _ = try await core.completeTask(id: task.id)
    let zone = TimeZone(identifier: today.timezone ?? "") ?? .current
    let shape = try await LorvexWeekShape.load(endingOn: todayKey, timeZone: zone, from: core)
    #expect(shape.days.last?.key == todayKey)
    #expect(shape.days.last?.finished == 1)
    #expect(shape.peak == 1)
  }
}
