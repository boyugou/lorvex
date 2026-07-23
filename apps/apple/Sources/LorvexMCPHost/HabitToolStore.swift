import MCP

extension ToolRegistry {
  func habitsPayload(date: String, includeStats: Bool = false) async throws -> [Value] {
    try await coreBridge.loadHabits(date: date, includeStats: includeStats)
  }

  func reorderHabitsPayload(orderedIDs: [String], date: String) async throws -> [Value] {
    try await coreBridge.reorderHabits(orderedIDs: orderedIDs, date: date)
  }

  func habitCompletionsPayload(id: String, from: String?, to: String?, limit: Int) async throws
    -> Value
  {
    try await coreBridge.getHabitCompletions(id: id, from: from, to: to, limit: limit)
  }

  func habitStatsPayload(id: String) async throws -> Value {
    try await coreBridge.getHabitStats(id: id)
  }

  func updateHabitPayload(id: String, arguments: [String: Value]) async throws -> Value {
    try await coreBridge.updateHabit(id: id, arguments: arguments)
  }

  func deleteHabitPayload(id: String, date: String) async throws -> Value {
    try await coreBridge.deleteHabit(id: id, date: date)
  }

  func batchCompleteHabitsPayload(ids: [String], date: String) async throws -> Value {
    try await coreBridge.batchCompleteHabits(ids: ids, date: date)
  }
}
