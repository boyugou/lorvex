import LorvexCore

extension LorvexTaskIntentRunner {
  public static func updateHabit(
    id: LorvexHabit.ID,
    name: String?,
    cue: String?,
    targetCount: Int?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.updateHabit(
        id: id,
        name: name,
        cue: cue,
        targetCount: targetCount,
        core: core
      )
    }
  }

  public static func deleteHabit(
    id: LorvexHabit.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit.ID {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.deleteHabit(id: id, core: core)
    }
  }

  public static func completeHabit(
    id: LorvexHabit.ID,
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.completeHabit(
        id: id,
        date: date,
        core: core
      )
    }
  }

  public static func uncompleteHabit(
    id: LorvexHabit.ID,
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.uncompleteHabit(
        id: id,
        date: date,
        core: core
      )
    }
  }

  public static func skipHabit(
    id: LorvexHabit.ID,
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.skipHabit(
        id: id,
        date: date,
        core: core
      )
    }
  }

  public static func unskipHabit(
    id: LorvexHabit.ID,
    date: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexHabit {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.unskipHabit(
        id: id,
        date: date,
        core: core
      )
    }
  }
}
