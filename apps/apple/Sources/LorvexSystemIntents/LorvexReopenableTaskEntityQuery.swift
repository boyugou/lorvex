import AppIntents
import LorvexCore

struct LorvexReopenableTaskEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexReopenableTaskEntity.ID]) async throws -> [LorvexReopenableTaskEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    var entities: [LorvexReopenableTaskEntity] = []
    for id in identifiers {
      if let entity = try? await Self.entity(id: id, core: core) {
        entities.append(entity)
      }
    }
    return entities
  }

  func suggestedEntities() async throws -> [LorvexReopenableTaskEntity] {
    try await Self.suggestedEntities(core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func entities(matching string: String) async throws -> [LorvexReopenableTaskEntity] {
    try await Self.entities(matching: string, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  static func entity(
    id: LorvexReopenableTaskEntity.ID,
    core: any LorvexCoreServicing
  ) async throws -> LorvexReopenableTaskEntity {
    LorvexReopenableTaskEntity(task: try await core.loadTask(id: id))
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws -> [LorvexReopenableTaskEntity] {
    let completed = try await core.listTasks(
      status: LorvexTask.Status.completed.rawValue,
      listID: nil,
      priority: nil,
      text: nil,
      limit: 50,
      offset: 0
    ).tasks
    let cancelled = try await core.listTasks(
      status: LorvexTask.Status.cancelled.rawValue,
      listID: nil,
      priority: nil,
      text: nil,
      limit: 50,
      offset: 0
    ).tasks
    // Only terminal tasks are reopenable. A deferred task stays `open` (defer
    // pushes planned_date), so it is never a reopen candidate.
    return (completed + cancelled)
      .map(LorvexReopenableTaskEntity.init(task:))
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexReopenableTaskEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return try await suggestedEntities(core: core) }
    let matches = try await core.searchTasks(query: query, status: "all", limit: 50, offset: 0).tasks
      .filter(\.status.isReopenable)
      .map(LorvexReopenableTaskEntity.init(task:))
    let entityMatches = try await suggestedEntities(core: core).filter { entity in
      entity.title.localizedCaseInsensitiveContains(query)
        || entity.id.localizedCaseInsensitiveContains(query)
        || entity.status.localizedCaseInsensitiveContains(query)
    }
    return deduplicatedReopenableEntities(matches + entityMatches)
  }
}

private extension LorvexTask.Status {
  var isReopenable: Bool {
    switch self {
    case .completed, .cancelled:
      true
    case .open, .inProgress, .someday:
      false
    }
  }
}

private func deduplicatedReopenableEntities(
  _ entities: [LorvexReopenableTaskEntity]
) -> [LorvexReopenableTaskEntity] {
  var seen = Set<LorvexReopenableTaskEntity.ID>()
  return entities.filter { entity in
    seen.insert(entity.id).inserted
  }
}
