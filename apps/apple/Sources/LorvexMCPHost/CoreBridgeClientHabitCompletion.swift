import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func completeHabit(id: String, date: String) async throws -> Value {
    let snapshot = try await service.completeHabit(id: id, date: date)
    guard let habit = snapshot.habits.first(where: { $0.id == id }) else {
      throw LorvexCoreError.unsupportedOperation("Habit '\(id)' not found after mutation.")
    }
    return Self.habitCompletionValue(from: habit)
  }

  func uncompleteHabit(id: String, date: String) async throws -> Value {
    let snapshot = try await service.uncompleteHabit(id: id, date: date)
    return try habitValue(in: snapshot, id: id)
  }

  func adjustHabitCompletion(id: String, date: String, delta: Int) async throws -> Value {
    let snapshot = try await service.adjustHabitCompletion(id: id, date: date, delta: delta)
    guard let habit = snapshot.habits.first(where: { $0.id == id }) else {
      throw LorvexCoreError.unsupportedOperation("Habit '\(id)' not found after mutation.")
    }
    // Carries `reached_milestone` (the milestone a positive adjust just crossed),
    // matching complete_habit / batch_complete_habits.
    return Self.habitCompletionValue(from: habit)
  }

  func batchCompleteHabits(ids: [String], date: String) async throws -> Value {
    let receipt = try await mcpMutations.batchCompleteHabitsForMcp(ids: ids, date: date)
    let afterByID = Dictionary(
      receipt.snapshot.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let completedIDs = Set(receipt.completedIDs)
    let notFoundIDs = Set(receipt.notFoundIDs)
    let alreadyCompleteIDs = Set(receipt.alreadyCompleteIDs)

    var completed: [Value] = []
    var skipped: [Value] = []
    for id in ids {
      if notFoundIDs.contains(id) {
        skipped.append(.object(["id": .string(id), "reason": .string("not found")]))
        continue
      }
      if alreadyCompleteIDs.contains(id) {
        skipped.append(.object(["id": .string(id), "reason": .string("already complete")]))
      } else if completedIDs.contains(id), let after = afterByID[id] {
        completed.append(Self.habitCompletionValue(from: after))
      } else {
        throw LorvexCoreError.unsupportedOperation(
          "Habit '\(id)' missing from its transactional completion receipt.")
      }
    }
    return .object([
      "results": .array(completed),
      "count": .int(completed.count),
      "date": .string(date),
      "skipped": .array(skipped),
    ])
  }

  func getHabitCompletions(id: String, from: String?, to: String?, limit: Int) async throws -> Value
  {
    // Fetch one extra row so the adapter can detect truncation without a
    // separate COUNT query, then render exactly `limit` in the page.
    let snapshot = try await service.getHabitCompletions(
      id: id,
      from: (from?.isEmpty ?? true) ? nil : from,
      to: (to?.isEmpty ?? true) ? nil : to,
      limit: limit + 1
    )
    return Self.habitCompletionsValue(from: snapshot, limit: limit)
  }

  func getHabitStats(id: String) async throws -> Value {
    Self.habitStatsValue(from: try await service.getHabitStats(id: id))
  }

  private func habitValue(in snapshot: HabitCatalogSnapshot, id: String) throws -> Value {
    guard let habit = snapshot.habits.first(where: { $0.id == id }) else {
      throw LorvexCoreError.unsupportedOperation("Habit '\(id)' not found after mutation.")
    }
    return Self.habitValue(from: habit)
  }
}
