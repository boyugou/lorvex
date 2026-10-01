import Foundation
import LorvexCore
import Testing

@Suite("Day times service")
struct DayTimesServiceTests {
  private static let day = "2099-01-01"

  @Test("a save replaces the unfinished times, keeps finished ones, and moves listed tasks onto the day")
  func saveReplacesTheUnfinishedTimes() async throws {
    let core = try makeInMemoryCore()
    let untimed = try await core.createTask(TaskCreateDraft(title: "Loses its time", priority: .p1))
    let finished = try await core.createTask(TaskCreateDraft(title: "Finished at nine"))
    let moved = try await core.createTask(TaskCreateDraft(title: "Planned for another day"))
    try await planTask(core, untimed.id, on: Self.day, time: 8 * 60..<9 * 60)
    try await planTask(core, finished.id, on: Self.day, time: 9 * 60..<10 * 60)
    try await planTask(core, moved.id, on: "2099-01-05")
    _ = try await core.completeTask(id: finished.id)

    let timed = try await core.saveDayTimes(
      date: Self.day, times: [LorvexTaskTime(taskID: moved.id, time: 14 * 60..<15 * 60)])

    #expect(timed.map(\.id) == [finished.id, moved.id])
    let untimedAfter = try await core.loadTask(id: untimed.id)
    #expect(untimedAfter.plannedTime == nil)
    #expect(untimedAfter.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == Self.day)
    #expect(try await core.loadTask(id: finished.id).plannedTime == 9 * 60..<10 * 60)
    let movedAfter = try await core.loadTask(id: moved.id)
    #expect(movedAfter.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == Self.day)
    #expect(movedAfter.plannedTime == 14 * 60..<15 * 60)
  }

  @Test("a save refuses a finished task and a task listed twice, and changes nothing")
  func saveRejectsFinishedAndRepeatedTasks() async throws {
    let core = try makeInMemoryCore()
    let open = try await core.createTask(TaskCreateDraft(title: "Open"))
    let finished = try await core.createTask(TaskCreateDraft(title: "Finished"))
    try await planTask(core, open.id, on: Self.day, time: 8 * 60..<9 * 60)
    _ = try await core.completeTask(id: finished.id)

    await #expect(throws: LorvexCoreError.self) {
      _ = try await core.saveDayTimes(
        date: Self.day, times: [LorvexTaskTime(taskID: finished.id, time: 10 * 60..<11 * 60)])
    }
    await #expect(throws: LorvexCoreError.self) {
      _ = try await core.saveDayTimes(
        date: Self.day,
        times: [
          LorvexTaskTime(taskID: open.id, time: 10 * 60..<11 * 60),
          LorvexTaskTime(taskID: open.id, time: 12 * 60..<13 * 60),
        ])
    }
    #expect(try await core.loadTask(id: open.id).plannedTime == 8 * 60..<9 * 60)
  }
}
