import LorvexCore

extension LorvexTaskIntentRunner {
  public static func updateList(
    id: LorvexList.ID,
    name: String?,
    description: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexList {
    try await LorvexSystemIntentRunner.updateList(
      id: id,
      name: name,
      description: description,
      core: core
    )
  }

  public static func deleteList(
    id: LorvexList.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexList.ID {
    try await LorvexSystemIntentRunner.deleteList(id: id, core: core)
  }

  public static func listAllTags(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [String] {
    try await LorvexSystemIntentRunner.listAllTags(core: core)
  }

  public static func renameTag(
    oldTag: String,
    newTag: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> String {
    try await LorvexSystemIntentRunner.renameTag(oldTag: oldTag, newTag: newTag, core: core)
  }

  public static func getTasksByTag(
    tag: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [LorvexTask] {
    try await LorvexSystemIntentRunner.getTasksByTag(tag: tag, core: core)
  }
}
