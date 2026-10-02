import AppIntents
import Foundation
import LorvexCore

struct LorvexHabitEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexHabitEntity.ID]) async throws -> [LorvexHabitEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      let habits = try await Self.allHabitEntities(core: core)
      let requested = Set(identifiers)
      return habits.filter { requested.contains($0.id) }
    }
  }

  func suggestedEntities() async throws -> [LorvexHabitEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.suggestedEntities(core: core)
    }
  }

  func entities(matching string: String) async throws -> [LorvexHabitEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexHabitEntity] {
    try await allHabitEntities(core: core)
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexHabitEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await allHabitEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { entity in
      entity.name.localizedStandardContains(query)
        || entity.id.localizedStandardContains(query)
    }
  }

  private static func allHabitEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexHabitEntity]
  {
    let logicalDay = try await core.getSessionContext().date
    return try await core.loadHabits(date: logicalDay).habits
      .filter { !$0.archived }
      .map(LorvexHabitEntity.init(habit:))
  }
}
