import AppIntents
import Foundation
import LorvexCore

struct LorvexHabitReminderEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexHabitReminderEntity.ID]) async throws
    -> [LorvexHabitReminderEntity]
  {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(for: identifiers, core: core)
    }
  }

  func suggestedEntities() async throws -> [LorvexHabitReminderEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.suggestedEntities(core: core)
    }
  }

  func entities(matching string: String) async throws -> [LorvexHabitReminderEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  static func entities(
    for identifiers: [LorvexHabitReminderEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexHabitReminderEntity] {
    let reminders = try await suggestedEntities(core: core)
    return identifiers.compactMap { id in reminders.first { $0.id == id } }
  }

  /// Every habit reminder, habit by habit in name order, each habit's
  /// reminders by clock time.
  static func suggestedEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexHabitReminderEntity]
  {
    try await core.getAllHabitReminderPolicies()
      .map(LorvexHabitReminderEntity.init(policy:))
      .sorted { lhs, rhs in
        switch lhs.habitName.localizedStandardCompare(rhs.habitName) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.reminderTime < rhs.reminderTime
        }
      }
  }

  /// Habit reminders whose habit name contains `string`.
  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexHabitReminderEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await suggestedEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { $0.habitName.containsSearchTerm(query) }
  }
}
