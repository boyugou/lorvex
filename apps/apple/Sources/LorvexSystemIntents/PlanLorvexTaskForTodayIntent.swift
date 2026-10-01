import AppIntents

struct PlanLorvexTaskForTodayIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.plan_today.title", defaultValue: "Plan Lorvex Task for Today", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.plan_today.description", defaultValue: "Plan a Lorvex task for today so it appears on Today.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(taskID: String) {
    task = LorvexTaskEntity(id: taskID, title: taskID, status: "")
  }

  init(task: LorvexTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let planned = try await LorvexTaskIntentRunner.planTaskForToday(id: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.plan_today.dialog", defaultValue: "Planned \(planned.title) for today.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
