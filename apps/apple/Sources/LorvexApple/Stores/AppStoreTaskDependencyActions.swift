import Foundation
import LorvexCore
import OSLog

private let dependencyEditLog = Logger(
  subsystem: "com.lorvex.app",
  category: "task-dependency")

extension AppStore {
  /// The task-detail draft's dependencies as an ordered, de-duplicated list of
  /// task IDs, projected over the same `taskDetailDependsOnText` the save path
  /// serializes. Reading parses the text; writing re-serializes it as a
  /// comma-separated string. Task IDs contain no comma / newline / tab, so the
  /// round-trip is lossless and both the dirty check
  /// (`parsedTaskDetailDependencies != task.dependsOn`) and the draft fingerprint
  /// (which hashes `taskDetailDependsOnText`) keep their existing semantics — the
  /// dependencies editor drives the identical save contract the raw text field
  /// did.
  var taskDetailDependencies: [LorvexTask.ID] {
    get { parsedTaskDetailDependencies }
    set { taskDetailDependsOnText = newValue.joined(separator: ", ") }
  }

  /// Candidate tasks for the dependency picker. An empty query lists actionable
  /// (open + in-progress) tasks; a non-empty query runs the core text search.
  /// `excludedIDs` (self, already-selected dependencies, and any cycle-creating
  /// task) are dropped from the results. A type-ahead read must never raise a
  /// blocking error banner, so a lookup failure degrades to an empty result and
  /// is logged rather than thrown.
  func dependencyCandidates(
    matching query: String,
    excluding excludedIDs: Set<LorvexTask.ID>
  ) async -> [LorvexTask] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      let tasks: [LorvexTask]
      if trimmed.isEmpty {
        tasks = try await core.listTasks(
          status: LorvexTask.Status.actionableFilter,
          listID: nil, priority: nil, text: nil, limit: 50, offset: 0
        ).tasks
      } else {
        tasks = try await core.searchTasks(
          query: trimmed, status: "all", limit: 50, offset: 0
        ).tasks
      }
      return tasks.filter { !excludedIDs.contains($0.id) }
    } catch {
      dependencyEditLog.error(
        "dependencyCandidates lookup failed: \(error.localizedDescription, privacy: .private)"
      )
      return []
    }
  }

  /// Resolves dependency IDs to their tasks for title display, preferring the
  /// loaded task pools and falling back to a single-task core load for any ID not
  /// present there. An ID that resolves to nothing (a deleted or archived target
  /// the core no longer returns) is simply omitted, and the row for it renders as
  /// an "unavailable" placeholder that is still removable.
  func dependencyTasks(for ids: [LorvexTask.ID]) async -> [LorvexTask] {
    var resolved: [LorvexTask] = []
    for id in ids {
      if let task = taskForDetailDraft(id: id) {
        resolved.append(task)
      } else if let task = try? await core.loadTask(id: id) {
        resolved.append(task)
      }
    }
    return resolved
  }

  /// Task IDs that must be excluded from `taskID`'s dependency picker because a
  /// new edge from `taskID` to them would close a cycle: `taskID` itself, plus
  /// every task that already (transitively) depends on `taskID`.
  ///
  /// This reuses the core's dependency-graph facility
  /// (`TaskRepoDependencyGraph` via `getDependencyGraph`) rather than reading the
  /// raw edge table: it fetches the whole graph (including inactive tasks) and
  /// walks reverse reachability from `taskID` — a task `C` reachable this way has
  /// a path `C → … → taskID`, so making `taskID` depend on `C` would create a
  /// cycle. The core still rejects a cycle at save time
  /// (`DependencyValidation.validateNoDependencyCycle`), so a stale or capped
  /// graph read can never let a cycle through; this only keeps cycle-creating
  /// candidates out of the picker up front. A graph read failure degrades to
  /// excluding only `taskID`, leaving the save-time check as the backstop.
  func dependencyCycleExclusions(for taskID: LorvexTask.ID) async -> Set<LorvexTask.ID> {
    var excluded: Set<LorvexTask.ID> = [taskID]
    guard
      let graph = try? await core.getDependencyGraph(
        rootTaskID: nil, listID: nil, includeInactive: true)
    else {
      return excluded
    }

    // Reverse adjacency: `dependents[X]` lists the tasks that directly depend on
    // `X` (each graph edge `from → to` means "from depends on to").
    var dependents: [LorvexTask.ID: [LorvexTask.ID]] = [:]
    for edge in graph.edges {
      dependents[edge.to, default: []].append(edge.from)
    }

    // Breadth-first over reverse edges from `taskID`; everything reached already
    // depends on `taskID`, transitively, and would form a cycle if selected.
    var frontier: [LorvexTask.ID] = [taskID]
    while let current = frontier.popLast() {
      for upstream in dependents[current] ?? [] where excluded.insert(upstream).inserted {
        frontier.append(upstream)
      }
    }
    return excluded
  }
}
