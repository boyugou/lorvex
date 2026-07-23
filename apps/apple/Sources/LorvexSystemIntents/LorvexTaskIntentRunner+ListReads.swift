import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readLists(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> ListCatalogSnapshot {
    try await LorvexSystemIntentRunner.readLists(core: core)
  }

  public static func readListDetail(
    id: LorvexList.ID,
    limit: Int? = nil,
    offset: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> ListDetailSnapshot {
    try await LorvexSystemIntentRunner.readListDetail(
      id: id,
      limit: limit,
      offset: offset,
      core: core
    )
  }

  public static func readListHealth(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> ListHealthSnapshot {
    try await LorvexSystemIntentRunner.readListHealth(core: core)
  }
}
