import Foundation
import LorvexCore
import LorvexDomain
import MCP

extension CoreBridgeClient {
  /// Load the active habit catalog for `date`. When `includeStats` is true each
  /// row is enriched with the streak/rate fields `get_habit_stats` computes, via
  /// one stats query per habit (bounded — the habit catalog is small); otherwise
  /// the plain per-day habit rows are returned.
  func loadHabits(date: String, includeStats: Bool = false) async throws -> [Value] {
    let habits = try await service.loadHabits(date: date).habits
    guard includeStats else { return habits.map(Self.habitValue(from:)) }
    var values: [Value] = []
    values.reserveCapacity(habits.count)
    for habit in habits {
      let stats = try await service.getHabitStats(id: habit.id)
      values.append(Self.habitValue(from: habit, stats: stats))
    }
    return values
  }

  func reorderHabits(orderedIDs: [String], date: String) async throws -> [Value] {
    try await service.reorderHabits(orderedIDs: orderedIDs, date: date).habits
      .map(Self.habitValue(from:))
  }

  func createHabit(
    name: String, cue: String?, icon: String?, color: String?, targetCount: Int,
    cadence: HabitCadenceInput, milestoneTarget: Int?, originalID: String? = nil
  ) async throws -> Value {
    let normalized = (cue?.isEmpty ?? true) ? nil : cue
    // With an `original_id`, resolve collision-or-create and produce the rich
    // response under one writer transaction. This keeps an existing archived
    // row and a newly inserted row equally race-free.
    if let originalID {
      try Self.validateImportOriginalID(originalID, kind: .habit)
      let exported = ExportHabit(
        id: originalID, name: name, cue: normalized ?? "", icon: icon, color: color,
        frequencyType: cadence.frequencyType, weekdays: cadence.weekdays ?? [],
        perPeriodTarget: cadence.perPeriodTarget, dayOfMonth: cadence.dayOfMonth,
        targetCount: targetCount, milestoneTarget: milestoneTarget)
      return Self.habitValue(from: try await mcpMutations.createHabitForMcpIfAbsent(exported))
    }
    return Self.habitValue(
      from: try await service.createHabit(
        name: name, cue: normalized, icon: icon, color: color, targetCount: targetCount,
        cadence: cadence, milestoneTarget: milestoneTarget))
  }

  func updateHabit(id: String, arguments: [String: Value]) async throws -> Value {
    // A supplied `frequency_type` replaces the whole cadence; omit it to leave
    // the cadence unchanged.
    let cadence = try StrictScalarArguments.optionalString(
      arguments["frequency_type"], field: "frequency_type")
      .map { try Self.habitCadenceInput(frequencyType: $0, arguments: arguments) }
    // Three-state milestone patch: absent key → unchanged, JSON null → clear,
    // a value → set.
    let milestone = try Self.intPatch(from: arguments, key: "milestone_target")
    let habit = try await service.updateHabit(
      id: id,
      name: try StrictScalarArguments.optionalString(arguments["name"], field: "name"),
      cue: try StrictScalarArguments.optionalString(arguments["cue"], field: "cue"),
      color: try StrictScalarArguments.optionalString(arguments["color"], field: "color"),
      icon: try StrictScalarArguments.optionalString(arguments["icon"], field: "icon"),
      targetCount: try StrictScalarArguments.optionalInt(
        arguments["target_count"], field: "target_count"),
      archived: try StrictScalarArguments.optionalBool(arguments["archived"], field: "archived"),
      cadence: cadence,
      milestoneTarget: milestone
    )
    return Self.habitValue(from: habit)
  }

  /// Build a typed ``HabitCadenceInput`` from MCP `create_habit` / `update_habit`
  /// arguments. `weekdays` is an array of Monday-first ints (0=Mon … 6=Sun);
  /// `per_period_target` and `day_of_month` carry the times-per-week count and
  /// monthly reminder day respectively.
  ///
  /// A non-integer `weekdays` element is rejected rather than silently dropped,
  /// so a malformed rhythm never quietly changes which days a habit is scheduled
  /// on. The domain range check (0…6 weekday, 1…31 day_of_month, known
  /// frequency_type, positive per_period_target) is applied by the core when it
  /// bridges the input to a `HabitCadence`.
  static func habitCadenceInput(
    frequencyType: String, arguments: [String: Value]
  ) throws -> HabitCadenceInput {
    let weekdays: [Int]?
    if let value = arguments["weekdays"], !value.isNull {
      guard let raw = value.arrayValue else {
        throw ValidationError.invalidFormat(
          field: "weekdays", expected: "an array of integers 0 (Mon) … 6 (Sun)",
          actual: StrictArgumentArray.describe(value))
      }
      weekdays = try raw.map { element in
        guard let int = element.intValue else {
          throw ValidationError.invalidFormat(
            field: "weekdays", expected: "integers 0 (Mon) … 6 (Sun)",
            actual: element.stringValue.map { "\"\($0)\"" } ?? "a non-integer value")
        }
        return int
      }
    } else {
      weekdays = nil
    }
    return HabitCadenceInput(
      frequencyType: frequencyType,
      weekdays: weekdays,
      perPeriodTarget: try StrictScalarArguments.optionalInt(
        arguments["per_period_target"], field: "per_period_target"),
      dayOfMonth: try StrictScalarArguments.optionalInt(
        arguments["day_of_month"], field: "day_of_month"))
  }

  func deleteHabit(id: String, date: String) async throws -> Value {
    let receipt = try await mcpMutations.deleteHabitForMcp(id: id)
    return .object([
      "deleted": .bool(receipt.deleted),
      "id": .string(id),
      "previous": receipt.previous.map(Self.habitValue(from:)) ?? .null,
    ])
  }
}
