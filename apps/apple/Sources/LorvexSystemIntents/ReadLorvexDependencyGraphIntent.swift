import AppIntents
import LorvexCore

struct ReadLorvexDependencyGraphIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.task.dependency.read.title", defaultValue: "Read Lorvex Task Dependencies", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.task.dependency.read.description", defaultValue: "Read the unfinished tasks a Lorvex task waits on, or, without a task, every task still waiting on another.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.task.parameter.task", defaultValue: "Task", table: "Localizable", bundle: SystemL10n.bundle))
  var rootTask: LorvexTaskEntity?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity?

  init() {
    rootTask = nil
    list = nil
  }

  init(rootTask: LorvexTaskEntity? = nil, list: LorvexListEntity? = nil) {
    self.rootTask = rootTask
    self.list = list
  }

  /// With a task, returns the unfinished tasks it waits on directly. Without
  /// one, returns every task still waiting on an unfinished task, in the
  /// picked list when there is one. The list narrows only that second read,
  /// so a task's dependencies in other lists are never hidden.
  func perform() async throws -> some IntentResult & ReturnsValue<[LorvexTaskEntity]> & ProvidesDialog {
    let graph = try await LorvexTaskIntentRunner.readDependencyGraph(
      rootTaskID: rootTask?.id,
      listID: rootTask == nil ? list?.id : nil,
      includeInactive: false
    )
    guard let rootTask else {
      let waiting = Self.waitingTasks(in: graph).map(Self.entity)
      guard !waiting.isEmpty else {
        return .result(
          value: [],
          dialog: IntentDialog(
            LocalizedStringResource(
              "system.task.dependency.read.waiting_none_dialog",
              defaultValue: "No task is waiting on another.",
              table: "Localizable", bundle: SystemL10n.bundle)))
      }
      let titles = SystemIntentListSummary.names(waiting.map(\.title), total: waiting.count)
      return .result(
        value: waiting,
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.task.dependency.read.waiting_dialog",
            defaultValue: "\(waiting.count) tasks are waiting on other tasks: \(titles)",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let waitsOn = Self.unfinishedDependencies(of: rootTask.id, in: graph).map(Self.entity)
    guard !waitsOn.isEmpty else {
      return .result(
        value: [],
        dialog: IntentDialog(
          LocalizedStringResource(
            "system.task.dependency.read.waits_on_none_dialog",
            defaultValue: "\(rootTask.title) isn’t waiting on any task.",
            table: "Localizable", bundle: SystemL10n.bundle)))
    }
    let titles = SystemIntentListSummary.names(waitsOn.map(\.title), total: waitsOn.count)
    return .result(
      value: waitsOn,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.task.dependency.read.waits_on_dialog",
          defaultValue: "\(rootTask.title) waits on \(waitsOn.count) tasks: \(titles)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }

  /// The tasks `taskID` depends on directly that are neither completed nor
  /// cancelled, in the graph's node order.
  static func unfinishedDependencies(
    of taskID: LorvexTask.ID, in graph: DependencyGraph
  ) -> [DependencyGraphNode] {
    let dependencyIDs = Set(graph.edges.filter { $0.from == taskID }.map(\.to))
    return graph.nodes.filter { dependencyIDs.contains($0.id) && isUnfinished($0) }
  }

  /// The graph's blocked tasks — those with a dependency still unfinished —
  /// in the graph's node order.
  static func waitingTasks(in graph: DependencyGraph) -> [DependencyGraphNode] {
    let blocked = Set(graph.blocked)
    return graph.nodes.filter { blocked.contains($0.id) && isUnfinished($0) }
  }

  private static func isUnfinished(_ node: DependencyGraphNode) -> Bool {
    node.status != LorvexTask.Status.completed.rawValue
      && node.status != LorvexTask.Status.cancelled.rawValue
  }

  private static func entity(_ node: DependencyGraphNode) -> LorvexTaskEntity {
    LorvexTaskEntity(id: node.id, title: node.title, status: node.status)
  }
}
