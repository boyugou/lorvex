extension LorvexSystemIntentRunner {
  public static func readLists(
    core: any LorvexCoreServicing
  ) async throws -> ListCatalogSnapshot {
    try await core.loadLists()
  }

  public static func readListDetail(
    id: LorvexList.ID,
    limit: Int?,
    offset: Int?,
    core: any LorvexCoreServicing
  ) async throws -> ListDetailSnapshot {
    try await core.loadListDetail(
      id: validatedListID(id),
      limit: min(max(1, limit ?? 50), 200),
      offset: max(0, offset ?? 0)
    )
  }

  public static func readListHealth(
    core: any LorvexCoreServicing
  ) async throws -> ListHealthSnapshot {
    try await core.getListHealthSnapshot()
  }
}
