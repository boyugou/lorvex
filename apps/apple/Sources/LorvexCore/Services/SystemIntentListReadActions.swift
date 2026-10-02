extension LorvexSystemIntentRunner {
  public static func readLists(
    core: any LorvexCoreServicing
  ) async throws -> ListCatalogSnapshot {
    try await core.loadLists()
  }

  public static func readListHealth(
    core: any LorvexCoreServicing
  ) async throws -> ListHealthSnapshot {
    try await core.getListHealthSnapshot()
  }
}
