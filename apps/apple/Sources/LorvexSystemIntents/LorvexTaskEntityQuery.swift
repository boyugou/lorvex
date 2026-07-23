import AppIntents
import LorvexCore

struct LorvexTaskEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexTaskEntity.ID]) async throws -> [LorvexTaskEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    var entities: [LorvexTaskEntity] = []
    for id in identifiers {
      if let entity = try? await LorvexTaskEntityQuery.entity(id: id, core: core) {
        entities.append(entity)
      }
    }
    return entities
  }

  func suggestedEntities() async throws -> [LorvexTaskEntity] {
    try await Self.suggestedEntities(core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func entities(matching string: String) async throws -> [LorvexTaskEntity] {
    try await Self.entities(matching: string, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  static func entity(
    id: LorvexTaskEntity.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexTaskEntity {
    LorvexTaskEntity(task: try await core.loadTask(id: id))
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexTaskEntity] {
    try await core.listTasks(
      status: "all",
      listID: nil,
      priority: nil,
      text: nil,
      limit: 50,
      offset: 0
    ).tasks
      .filter { $0.status.isActive }
      .map(LorvexTaskEntity.init(task:))
  }

  /// Resolves a Spotlight/Siri search string against the whole task corpus via
  /// the core's text index (`searchTasks`), not just today's open tasks. An
  /// empty/whitespace query falls back to `suggestedEntities` (active
  /// tasks). Searches with `status: "all"` and drops completed/cancelled
  /// results afterward, matching `suggestedEntities`' active-task scope — the
  /// core's `"open"` search filter would also exclude someday/deferred tasks.
  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTaskEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return try await suggestedEntities(core: core) }
    let result = try await core.searchTasks(query: query, status: "all", limit: 50, offset: 0)
    return result.tasks
      .filter { $0.status.isActive }
      .map(LorvexTaskEntity.init(task:))
  }
}
