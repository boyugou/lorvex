import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readTask(
    id: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.readTask(id: id, core: core)
  }

  public static func readUpcomingTasks(
    daysAhead: Int? = nil,
    limit: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [LorvexTask] {
    try await LorvexSystemIntentRunner.readUpcomingTasks(
      daysAhead: daysAhead,
      limit: limit,
      core: core
    )
  }

  public static func searchTasks(
    query: String,
    status: String? = nil,
    limit: Int? = nil,
    offset: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskSearchResult {
    try await LorvexSystemIntentRunner.searchTasks(
      query: query,
      status: status,
      limit: limit,
      offset: offset,
      core: core
    )
  }

  public static func listTasks(
    status: String? = nil,
    listID: LorvexList.ID? = nil,
    priority: Int? = nil,
    text: String? = nil,
    limit: Int? = nil,
    offset: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskPageResult {
    try await LorvexSystemIntentRunner.listTasks(
      status: status,
      listID: listID,
      priority: priority,
      text: text,
      limit: limit,
      offset: offset,
      core: core
    )
  }

  public static func readDeferredTasks(
    listID: LorvexList.ID? = nil,
    limit: Int? = nil,
    offset: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskPageResult {
    try await LorvexSystemIntentRunner.readDeferredTasks(
      listID: listID,
      limit: limit,
      offset: offset,
      core: core
    )
  }

  public static func readDependencyGraph(
    rootTaskID: LorvexTask.ID? = nil,
    listID: LorvexList.ID? = nil,
    includeInactive: Bool = false,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> DependencyGraph {
    try await LorvexSystemIntentRunner.readDependencyGraph(
      rootTaskID: rootTaskID,
      listID: listID,
      includeInactive: includeInactive,
      core: core
    )
  }
}
