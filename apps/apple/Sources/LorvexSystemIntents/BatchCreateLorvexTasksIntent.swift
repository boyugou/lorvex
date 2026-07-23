import AppIntents

struct BatchCreateLorvexTasksIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.batch.create.title", defaultValue: "Batch Create Lorvex Tasks", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.batch.create.description", defaultValue: "Create multiple Lorvex tasks from titles.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.batch.parameter.titles", defaultValue: "Task Titles", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.task.batch.parameter.titles_description", defaultValue: "Comma or newline separated task titles.", table: "Localizable", bundle: SystemL10n.bundle))
  var titles: String

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.notes", defaultValue: "Notes", table: "Localizable", bundle: SystemL10n.bundle))
  var notes: String?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.priority", defaultValue: "Priority", table: "Localizable", bundle: SystemL10n.bundle))
  var priority: Int?

  init() {
    titles = ""
    notes = nil
    list = nil
    priority = nil
  }

  init(titles: String, notes: String? = nil, list: LorvexListEntity? = nil, priority: Int? = nil) {
    self.titles = titles
    self.notes = notes
    self.list = list
    self.priority = priority
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let tasks = try await LorvexTaskIntentRunner.batchCreateTasks(
      titlesText: titles,
      notes: notes,
      listID: list?.id,
      priority: priority
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.batch.create.dialog", defaultValue: "Created \(tasks.count) Lorvex tasks.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
