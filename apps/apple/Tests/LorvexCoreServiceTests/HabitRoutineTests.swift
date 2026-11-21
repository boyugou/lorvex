import Foundation
import LorvexDomain
import Testing

@testable import LorvexCore

@Suite("Morning and evening routines")
struct HabitRoutineTests {
  let friday = "2026-11-20"

  @Test(
    "Ordered membership and clock times follow habits to another device, even when the preference arrives first"
  )
  func syncAndDayBoundaries() async throws {
    let mac = try SwiftLorvexCoreService.inMemory()
    let phone = try SwiftLorvexCoreService.inMemory()
    let water = try await mac.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 3, cadence: .daily)
    let read = try await mac.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    let monday = try await mac.createHabit(
      name: "Gym", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "weekly", weekdays: [0]))
    let morning = HabitRoutine(startMinutes: 420, habitIDs: [read.id, monday.id, water.id])
    let evening = HabitRoutine(startMinutes: 1320, habitIDs: [water.id])
    try await mac.saveHabitRoutine(morning, for: .morning)
    try await mac.saveHabitRoutine(evening, for: .evening)
    let records = try mac.pendingOutbound().map(\.envelope)
    let prefs = records.filter { $0.entityType == .preference }
    #expect(prefs.count == 2)
    #expect(prefs.allSatisfy { $0.payloadSchemaVersion == 4 })
    #expect(records.filter { $0.entityType == .habit }.allSatisfy { $0.payloadSchemaVersion == 3 })
    _ = try phone.applyInbound(prefs, undecodable: 0)
    let empty = try await phone.loadHabits(date: friday)
    #expect(!empty.hasConfiguredRoutine)
    #expect(empty.routines.morning == morning)
    _ = try phone.applyInbound(records.filter { $0.entityType == .habit }, undecodable: 0)
    let catalog = try await phone.loadHabits(date: friday)
    #expect(catalog.hasConfiguredRoutine)
    #expect(catalog.routines.evening == evening)
    #expect(
      catalog.routines.members(.morning, on: friday, habits: catalog.habits).map(\.id) == [
        read.id, water.id,
      ])
    #expect(catalog.unassignedHabits(on: friday).isEmpty)
    #expect(catalog.routines.current(at: 419, habits: catalog.habits) == .evening)
    #expect(catalog.routines.current(at: 420, habits: catalog.habits) == .morning)
    #expect(catalog.routines.current(at: 1319, habits: catalog.habits) == .morning)
    #expect(catalog.routines.current(at: 1320, habits: catalog.habits) == .evening)
    let steps = catalog.routines.members(.morning, on: friday, habits: catalog.habits)
    #expect(catalog.routines.showsSteps(.morning, at: 539, rows: steps))
    #expect(!catalog.routines.showsSteps(.morning, at: 540, rows: steps))
    _ = try await phone.updateHabit(
      id: water.id, name: nil, cue: .unset, color: nil, icon: nil,
      targetCount: nil, archived: true)
    let archived = try await phone.loadHabits(date: friday)
    #expect(archived.routines.members(.evening, on: friday, habits: archived.habits).isEmpty)
    #expect(archived.routines.current(at: 1320, habits: archived.habits) == .morning)
    _ = try await phone.updateHabit(
      id: water.id, name: nil, cue: .unset, color: nil, icon: nil,
      targetCount: nil, archived: false)
    try await phone.saveHabitRoutine(HabitRoutine(startMinutes: 400), for: .morning)
    let solo = try await phone.loadHabits(date: friday)
    #expect(solo.routines.current(at: 420, habits: solo.habits) == .evening)
    #expect(solo.unassignedHabits(on: friday).map(\.id) == [read.id])
  }

  @Test("Three check-ins, a partial count and an excused day reconcile in Today, Habits and Review")
  func dayRecord() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let tea = try await core.createHabit(
      name: "Tea", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    let water = try await core.createHabit(
      name: "Water", cue: nil, icon: nil, color: nil, targetCount: 2, cadence: .daily)
    let walk = try await core.createHabit(
      name: "Walk", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily)
    let ids = [water.id, walk.id, tea.id]
    try await core.saveHabitRoutine(HabitRoutine(startMinutes: 420, habitIDs: ids), for: .morning)
    try await core.saveHabitRoutine(
      HabitRoutine(startMinutes: 1320, habitIDs: [water.id]), for: .evening)
    _ = try await core.completeHabit(id: tea.id, date: friday)
    _ = try await core.adjustHabitCompletion(id: water.id, date: friday, delta: 1)
    let catalog = try await core.completeHabit(id: walk.id, date: friday)
    #expect(
      catalog.routines.members(.morning, on: friday, habits: catalog.habits).map(\.completionsToday)
        == [1, 1, 1])
    let partial = try await core.loadDaySummary(date: friday)
    #expect(partial.habitsCompleted == 2)
    #expect(partial.habitsTotal == 3)
    _ = try await core.adjustHabitCompletion(id: water.id, date: friday, delta: 1)
    let met = try await core.loadDaySummary(date: friday)
    #expect(met.habitsCompleted == 3)
    _ = try await core.adjustHabitCompletion(id: water.id, date: friday, delta: -1)
    _ = try await core.uncompleteHabit(id: walk.id, date: friday)
    let skipped = try await core.skipHabit(id: walk.id, date: friday)
    let rows = skipped.routines.members(.morning, on: friday, habits: skipped.habits)
    #expect(rows.map(\.id) == ids)
    #expect(rows[1].isSkipped)
    #expect(
      skipped.routines.members(.evening, on: friday, habits: skipped.habits).first?.completionsToday
        == 1)
    let review = try await core.loadDaySummary(date: friday)
    #expect(review.habitsTotal == 2 && review.habitsCompleted == 1)
    let restored = try await core.unskipHabit(id: walk.id, date: friday)
    #expect(restored.habits.first(where: { $0.id == walk.id })?.isSkipped == false)
  }

  @Test("Invalid membership and clock values leave the saved routine intact")
  func invalidInputs() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let id = UUID().uuidString.lowercased()
    let good = HabitRoutine(startMinutes: 0, habitIDs: [id])
    try await core.saveHabitRoutine(good, for: .morning)
    for invalid in [
      HabitRoutine(startMinutes: -1), HabitRoutine(startMinutes: 1440),
      HabitRoutine(startMinutes: 0, habitIDs: [id, id]),
      HabitRoutine(startMinutes: 1, habitIDs: ["oops"]),
    ] {
      await #expect(throws: (any Error).self) {
        try await core.saveHabitRoutine(invalid, for: .morning)
      }
    }
    #expect(try await core.loadHabits(date: friday).routines.morning == good)
  }
}
