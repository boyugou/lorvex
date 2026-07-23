import AppIntents
import LorvexCore

struct LorvexAIMemoryEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexAIMemoryEntity.ID]) async throws -> [LorvexAIMemoryEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await Self.entities(for: identifiers, core: core)
  }

  func suggestedEntities() async throws -> [LorvexAIMemoryEntity] {
    try await Self.suggestedEntities(core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func entities(matching string: String) async throws -> [LorvexAIMemoryEntity] {
    try await Self.entities(matching: string, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  static func entities(
    for identifiers: [LorvexAIMemoryEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexAIMemoryEntity] {
    let entries = try await aiEntries(core: core)
    return identifiers.compactMap { id in
      entries.first { $0.key == id }.map(LorvexAIMemoryEntity.init(entry:))
    }
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexAIMemoryEntity] {
    try await aiEntries(core: core).map(LorvexAIMemoryEntity.init(entry:))
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexAIMemoryEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await suggestedEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { $0.key.localizedCaseInsensitiveContains(query) }
  }

  private static func aiEntries(core: any LorvexCoreServicing) async throws -> [MemoryEntry] {
    try await core.loadMemory().entries
  }
}
