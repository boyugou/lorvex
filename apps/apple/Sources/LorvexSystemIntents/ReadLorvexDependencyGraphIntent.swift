import AppIntents

struct ReadLorvexDependencyGraphIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.dependency.read.title", defaultValue: "Read Lorvex Dependency Graph", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.dependency.read.description", defaultValue: "Read Lorvex task dependency graph.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var rootTask: LorvexTaskEntity?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity?

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.include_inactive", defaultValue: "Include Inactive", table: "Localizable", bundle: SystemL10n.bundle))
  var includeInactive: Bool

  init() {
    rootTask = nil
    list = nil
    includeInactive = false
  }

  init(rootTask: LorvexTaskEntity? = nil, list: LorvexListEntity? = nil, includeInactive: Bool = false) {
    self.rootTask = rootTask
    self.list = list
    self.includeInactive = includeInactive
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let graph = try await LorvexTaskIntentRunner.readDependencyGraph(
      rootTaskID: rootTask?.id,
      listID: list?.id,
      includeInactive: includeInactive
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.dependency.read.dialog",
          defaultValue: "Tasks: \(graph.nodes.count), dependencies: \(graph.edges.count).",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
