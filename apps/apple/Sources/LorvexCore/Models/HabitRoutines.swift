import Foundation
import LorvexDomain

public struct HabitRoutines: Equatable, Sendable {
  public var morning = HabitRoutinePeriod.morning.defaultRoutine
  public var evening = HabitRoutinePeriod.evening.defaultRoutine

  public init() {}

  public subscript(period: HabitRoutinePeriod) -> HabitRoutine {
    get { period == .morning ? morning : evening }
    set {
      switch period {
      case .morning: morning = newValue
      case .evening: evening = newValue
      }
    }
  }

  /// The most recently started routine, wrapping through midnight. When only
  /// one routine has live members it owns the section throughout the day.
  public func current(at minutes: Int?, habits: [LorvexHabit]) -> HabitRoutinePeriod {
    let live = Set(habits.filter { !$0.archived }.map(\.id))
    let hasMorning = !live.isDisjoint(with: morning.habitIDs)
    let hasEvening = !live.isDisjoint(with: evening.habitIDs)
    if hasMorning != hasEvening { return hasMorning ? .morning : .evening }
    guard let minutes else { return .morning }
    let morningAge = (minutes - morning.startMinutes + 1440) % 1440
    let eveningAge = (minutes - evening.startMinutes + 1440) % 1440
    return morningAge <= eveningAge ? .morning : .evening
  }

  /// A routine opens on its steps during the first two hours after its start.
  /// Later in the day, or once everything is checked or excused, one line
  /// leaves room for work and the calendar. The disclosure always overrides it.
  public func showsSteps(_ period: HabitRoutinePeriod, at minutes: Int?, rows: [LorvexHabit])
    -> Bool
  {
    guard rows.contains(where: { !$0.isSkipped && $0.completionsToday < max(1, $0.targetCount) })
    else { return false }
    guard let minutes else { return true }
    return (minutes - self[period].startMinutes + 1440) % 1440 < 120
  }

  public func members(_ period: HabitRoutinePeriod, on day: String, habits: [LorvexHabit])
    -> [LorvexHabit]
  {
    let listed = Dictionary(
      habits.filter { !$0.archived && $0.isListed(on: day) }.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first })
    return self[period].habitIDs.compactMap { listed[$0] }
  }
}

extension LorvexCoreServicing {
  public func saveHabitRoutine(_ routine: HabitRoutine, for period: HabitRoutinePeriod) async throws
  {
    let data = try JSONEncoder().encode(routine)
    _ = try await setPreference(
      key: period.preferenceKey, value: String(decoding: data, as: UTF8.self))
  }
}

extension HabitCatalogSnapshot {
  public var hasConfiguredRoutine: Bool {
    let ids = Set(routines.morning.habitIDs + routines.evening.habitIDs)
    return habits.contains { !$0.archived && ids.contains($0.id) }
  }

  public func unassignedHabits(on day: String) -> [LorvexHabit] {
    let assigned = Set(routines.morning.habitIDs + routines.evening.habitIDs)
    return habits.filter { !$0.archived && !assigned.contains($0.id) && $0.isListed(on: day) }
  }
}
