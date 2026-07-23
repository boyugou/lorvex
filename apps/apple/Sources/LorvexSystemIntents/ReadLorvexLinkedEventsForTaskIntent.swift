import AppIntents

struct ReadLorvexLinkedEventsForTaskIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.calendar.linked_events_for_task.read.title", defaultValue: "Read Lorvex Linked Events for Task", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.calendar.linked_events_for_task.read.description", defaultValue: "Read calendar events linked to a Lorvex task.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var task: LorvexTaskEntity

  init() {
    task = LorvexTaskEntity(id: "", title: "", status: "")
  }

  init(task: LorvexTaskEntity) {
    self.task = task
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let events = try await LorvexTaskIntentRunner.readLinkedEventsForTask(taskID: task.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.calendar.linked_events_for_task.read.dialog_count",
          defaultValue: "\(task.title) has \(events.count) linked calendar events.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
