import AppIntents
import LorvexCore

struct LorvexListEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexListEntity.ID]) async throws -> [LorvexListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      let lists = try await Self.allListEntities(core: core)
      let requested = Set(identifiers)
      return lists.filter { requested.contains($0.id) }
    }
  }

  func suggestedEntities() async throws -> [LorvexListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.suggestedEntities(core: core)
    }
  }

  func entities(matching string: String) async throws -> [LorvexListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexListEntity] {
    try await allListEntities(core: core)
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexListEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await allListEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { entity in
      entity.name.localizedStandardContains(query)
        || entity.id.localizedStandardContains(query)
    }
  }

  private static func allListEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexListEntity]
  {
    try await core.loadLists().lists.map(LorvexListEntity.init(list:))
  }
}
