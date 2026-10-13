import GRDB
import XCTest

@testable import LorvexCore

/// A habit update whose every value is already the habit's own writes nothing:
/// no new version, no sync upsert, no changelog row. A real change writes one of
/// each.
final class HabitUpdateNoChangeTests: XCTestCase {
  private func counts(_ service: SwiftLorvexCoreService) throws -> (changelog: Int, outbox: Int, version: String) {
    try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = 'habit'") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'habit'") ?? -1,
        try String.fetchOne(db, sql: "SELECT version FROM habits LIMIT 1") ?? ""
      )
    }
  }

  func testRestatingCurrentValuesWritesNothingAndAChangeWritesOnce() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let habit = try await service.createHabit(
      name: "Read", cue: "After coffee", icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "daily"), milestoneTarget: nil)
    let created = try counts(service)

    // The same name, target, and a not-archived flag the habit already has.
    let same = try await service.updateHabit(
      id: habit.id, name: "Read", cue: .unset, color: nil, icon: nil, targetCount: 1,
      archived: false, cadence: HabitCadenceInput(frequencyType: "daily"))
    XCTAssertEqual(same.id, habit.id)
    let afterSame = try counts(service)
    XCTAssertEqual(afterSame.changelog, created.changelog, "no changelog row for no change")
    XCTAssertEqual(afterSame.outbox, created.outbox, "no sync upsert for no change")
    XCTAssertEqual(afterSame.version, created.version, "no new version for no change")

    // A real change writes one changelog row and moves the version.
    _ = try await service.updateHabit(
      id: habit.id, name: "Read a chapter", cue: .unset, color: nil, icon: nil, targetCount: nil,
      archived: nil, cadence: nil)
    let afterChange = try counts(service)
    XCTAssertEqual(afterChange.changelog, created.changelog + 1)
    XCTAssertNotEqual(afterChange.version, created.version)
  }

  func testAChangedWeekdaySetIsAChangeEvenWithTheSameFrequencyType() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let habit = try await service.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2]), milestoneTarget: nil)
    let before = try counts(service)

    _ = try await service.updateHabit(
      id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil, archived: nil,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2]))
    XCTAssertEqual(try counts(service).changelog, before.changelog, "the same weekdays are no change")

    _ = try await service.updateHabit(
      id: habit.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil, archived: nil,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 3]))
    XCTAssertEqual(try counts(service).changelog, before.changelog + 1, "other weekdays are a change")
  }
}
