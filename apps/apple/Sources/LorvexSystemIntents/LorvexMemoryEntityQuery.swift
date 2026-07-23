import AppIntents
import LorvexCore

struct LorvexMemoryEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexMemoryEntity.ID]) async throws -> [LorvexMemoryEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await Self.entities(for: identifiers, core: core)
  }

  func suggestedEntities() async throws -> [LorvexMemoryEntity] {
    try await Self.suggestedEntities(core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func entities(matching string: String) async throws -> [LorvexMemoryEntity] {
    try await Self.entities(matching: string, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  static func entities(
    for identifiers: [LorvexMemoryEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexMemoryEntity] {
    let entries = try await core.loadMemory().entries
    return identifiers.compactMap { id in
      entries.first { $0.key == id }.map(LorvexMemoryEntity.init(entry:))
    }
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexMemoryEntity] {
    try await core.loadMemory().entries.map(LorvexMemoryEntity.init(entry:))
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexMemoryEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await suggestedEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { entity in
      entity.key.localizedCaseInsensitiveContains(query)
    }
  }
}
