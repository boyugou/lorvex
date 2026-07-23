import LorvexCore

extension LorvexTaskIntentRunner {
  public static func updateTask(
    id: LorvexTask.ID,
    title: String? = nil,
    notes: String? = nil,
    priority: Int? = nil,
    estimatedMinutes: Int? = nil,
    plannedDate: String? = nil,
    tagsText: String? = nil,
    dependsOnText: String? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> LorvexTask {
    try await LorvexSystemIntentRunner.updateTask(
      id: id,
      title: title,
      notes: notes,
      priority: priority,
      estimatedMinutes: estimatedMinutes,
      plannedDate: plannedDate,
      tagsText: tagsText,
      dependsOnText: dependsOnText,
      core: core
    )
  }
}
