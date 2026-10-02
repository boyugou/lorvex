import AppIntents
import Foundation
import LorvexCore

struct LorvexChecklistItemEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexChecklistItemEntity.ID]) async throws
    -> [LorvexChecklistItemEntity]
  {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(for: identifiers, core: core)
    }
  }

  func suggestedEntities() async throws -> [LorvexChecklistItemEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.suggestedEntities(core: core)
    }
  }

  func entities(matching string: String) async throws -> [LorvexChecklistItemEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await LorvexIntentFailure.rewording(core: core) {
      try await Self.entities(matching: string, core: core)
    }
  }

  /// Each identifier's item, read from its own task. An identifier whose task
  /// or item no longer exists is left out.
  static func entities(
    for identifiers: [LorvexChecklistItemEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexChecklistItemEntity] {
    var tasks: [LorvexTask.ID: LorvexTask] = [:]
    var entities: [LorvexChecklistItemEntity] = []
    for identifier in identifiers {
      guard let parts = LorvexChecklistItemEntity.components(of: identifier) else { continue }
      if tasks[parts.taskID] == nil {
        tasks[parts.taskID] = try? await core.loadTask(id: parts.taskID)
      }
      guard let task = tasks[parts.taskID],
        let item = task.checklistItems.first(where: { $0.id == parts.itemID })
      else { continue }
      entities.append(LorvexChecklistItemEntity(item: item, task: task))
    }
    return entities
  }

  /// The checklist items of tasks still in play — open, started, and someday —
  /// task by task in the canonical task order, each task's items in their
  /// checklist order.
  static func suggestedEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexChecklistItemEntity]
  {
    let actionable = try await core.listTasks(
      status: LorvexTask.Status.actionableFilter, listID: nil, priority: nil, text: nil,
      limit: 200, offset: 0
    ).tasks
    let someday = try await core.listTasks(
      status: LorvexTask.Status.someday.rawValue, listID: nil, priority: nil, text: nil,
      limit: 100, offset: 0
    ).tasks
    return (actionable + someday).flatMap { task in
      task.checklistItems
        .sorted { $0.position < $1.position }
        .map { LorvexChecklistItemEntity(item: $0, task: task) }
    }
  }

  /// Suggested items whose text or task title contains `string`.
  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexChecklistItemEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await suggestedEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { entity in
      entity.text.localizedStandardContains(query)
        || entity.taskTitle.localizedStandardContains(query)
    }
  }
}
