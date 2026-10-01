import Foundation
import LorvexDomain
import Testing

@testable import LorvexCore

/// Suggested times for today start from the current time, never from a
/// morning that has already passed, and keep a task whose time is under way
/// where it is.
@Suite("Day times proposal start")
struct DayTimesProposalStartTests {
  private static func utcInstant(_ iso: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: iso))
  }

  /// Plan `taskID` for `date` with `minutes` of estimated work.
  private static func plan(
    _ service: SwiftLorvexCoreService, taskID: LorvexTask.ID, date: String, minutes: Int
  ) async throws {
    let day = try #require(SwiftLorvexTaskDeserializers.plannedDateFormatter.date(from: date))
    _ = try await service.updateTask(
      TaskUpdateDraft(id: taskID, estimatedMinutes: .set(minutes), plannedDate: .set(day)))
  }

  @Test("today's floor is the current time rounded up to five minutes")
  func todayFloorRoundsUp() throws {
    func floor(_ iso: String) throws -> String? {
      SwiftLorvexCoreService.proposalStartFloor(
        date: "2026-03-04", timezoneName: "UTC", now: try Self.utcInstant(iso)
      )?.asString
    }
    #expect(try floor("2026-03-04T12:59:30Z") == "13:00")
    #expect(try floor("2026-03-04T13:00:10Z") == "13:00")
    #expect(try floor("2026-03-04T13:01:00Z") == "13:05")
    #expect(try floor("2026-03-04T23:58:00Z") == "23:59", "the last minutes saturate at 23:59")
  }

  @Test("another day, or today in a different timezone, has no floor")
  func otherDaysHaveNoFloor() throws {
    let now = try Self.utcInstant("2026-03-04T15:30:00Z")
    #expect(
      SwiftLorvexCoreService.proposalStartFloor(
        date: "2026-03-05", timezoneName: "UTC", now: now) == nil)
    // 15:30 UTC is already 00:30 on 2026-03-05 in Tokyo, so 2026-03-04 is not
    // today there, and 2026-03-05 starts from half past midnight.
    #expect(
      SwiftLorvexCoreService.proposalStartFloor(
        date: "2026-03-04", timezoneName: "Asia/Tokyo", now: now) == nil)
    #expect(
      SwiftLorvexCoreService.proposalStartFloor(
        date: "2026-03-05", timezoneName: "Asia/Tokyo", now: now)?.asString == "00:30")
  }

  @Test("a suggestion for today starts now, and tomorrow's at the day-hours start")
  func proposalForTodayStartsNow() async throws {
    let now = try Self.utcInstant("2026-03-04T12:59:00Z")
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { now })
    _ = try await service.setPreference(key: "timezone", value: #""UTC""#)
    let task = try await service.createTask(title: "Write the brief", notes: "")
    try await Self.plan(service, taskID: task.id, date: "2026-03-04", minutes: 30)

    let today = try await service.proposeDayTimes(date: "2026-03-04")
    #expect(today.placements.map(\.task.id) == [task.id])
    #expect(today.placements.first?.time == 780..<810)

    // The task is still open tomorrow, so tomorrow's suggestion carries it.
    let tomorrow = try await service.proposeDayTimes(date: "2026-03-05")
    #expect(tomorrow.placements.first?.time == 480..<510)
  }

  @Test("a suggestion for today keeps the time under way and places the rest after it")
  func proposalKeepsTheTimeUnderWay() async throws {
    let now = try Self.utcInstant("2026-03-04T11:20:00Z")
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { now })
    _ = try await service.setPreference(key: "timezone", value: #""UTC""#)
    var taskIDs: [String] = []
    for (title, minutes) in [("Draft the agenda", 90), ("Send the update", 60)] {
      let task = try await service.createTask(title: title, notes: "")
      try await Self.plan(service, taskID: task.id, date: "2026-03-04", minutes: minutes)
      taskIDs.append(task.id)
    }
    _ = try await service.saveDayTimes(
      date: "2026-03-04", times: [LorvexTaskTime(taskID: taskIDs[1], time: 655..<715)])

    let proposal = try await service.proposeDayTimes(date: "2026-03-04")
    #expect(proposal.placements.map(\.task.id) == [taskIDs[1], taskIDs[0]])
    #expect(
      proposal.placements.map(\.time) == [655..<715, 725..<815],
      "the running time stays; the rest follows a break")
  }

  private static func task(_ id: String, _ title: String) -> LorvexTask {
    LorvexTask(
      id: id, title: title, notes: "", priority: .p2, status: .open, dueDate: nil,
      estimatedMinutes: nil, tags: [])
  }

  @Test("placesNothing is true only when tasks were left and none was placed")
  func placesNothing() {
    let left = Self.task("t-2", "Left over")
    let placed = DayTimesProposal.Placement(task: Self.task("t-1", "Placed"), time: 780..<810)
    #expect(
      DayTimesProposal(
        date: "2026-03-04", workingHours: 540..<1020, availableMinutes: 0, placements: [],
        unscheduled: [left]
      ).placesNothing)
    #expect(
      !DayTimesProposal(
        date: "2026-03-04", workingHours: 540..<1020, availableMinutes: 240,
        placements: [placed], unscheduled: [left]
      ).placesNothing)
    #expect(
      !DayTimesProposal(
        date: "2026-03-04", workingHours: 540..<1020, availableMinutes: 480, placements: []
      ).placesNothing)
  }
}
