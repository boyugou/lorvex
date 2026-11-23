import LorvexCore

/// The work behind the Siri reminder actions. Each one runs the matching
/// ``LorvexSystemIntentRunner`` action and wraps what it returns as the entity
/// Siri reads, in one pass through ``LorvexIntentFailure/rewording(core:_:)``.
@available(macOS 27.0, iOS 27.0, *)
extension LorvexTaskIntentRunner {
  static func createSiriTask(
    _ fields: SiriTaskFields,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexSiriTaskEntity {
    try await LorvexIntentFailure.rewording(core: core) {
      let task = try await LorvexSystemIntentRunner.createSiriTask(fields, core: core)
      return try await siriEntity(for: task, core: core)
    }
  }

  static func updateSiriTask(
    id: LorvexTask.ID,
    fields: SiriTaskFields,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexSiriTaskEntity {
    try await LorvexIntentFailure.rewording(core: core) {
      let task = try await LorvexSystemIntentRunner.updateSiriTask(
        id: id, fields: fields, core: core)
      return try await siriEntity(for: task, core: core)
    }
  }

  /// Cancels the tasks; see ``LorvexSystemIntentRunner/cancelSiriTasks(ids:core:)``.
  static func cancelSiriTasks(
    ids: [LorvexTask.ID],
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskBatchCancelByIdResult {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.cancelSiriTasks(ids: ids, core: core)
    }
  }

  static func createSiriList(
    name: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexSiriListEntity {
    try await LorvexIntentFailure.rewording(core: core) {
      LorvexSiriListEntity(
        list: try await LorvexSystemIntentRunner.createList(
          name: name, description: nil, core: core))
    }
  }

  private static func siriEntity(
    for task: LorvexTask, core: any LorvexCoreServicing
  ) async throws -> LorvexSiriTaskEntity {
    guard
      let entity = try await LorvexSiriTaskEntityQuery.entities(wrapping: [task], core: core).first
    else { throw LorvexCoreError.taskNotFound }
    return entity
  }
}
