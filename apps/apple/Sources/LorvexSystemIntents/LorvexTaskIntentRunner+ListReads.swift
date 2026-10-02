import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readLists(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> ListCatalogSnapshot {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.readLists(core: core)
    }
  }

  public static func readListHealth(
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> ListHealthSnapshot {
    try await LorvexIntentFailure.rewording(core: core) {
      try await LorvexSystemIntentRunner.readListHealth(core: core)
    }
  }
}
