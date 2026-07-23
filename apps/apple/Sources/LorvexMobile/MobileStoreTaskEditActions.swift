import Foundation
import LorvexCore
import OSLog

private let taskEditLog = Logger(
  subsystem: "com.lorvex.mobile",
  category: "task-edit")

extension MobileStore {
  /// Distinct tag names already in use across loaded task pools, sorted
  /// case-insensitively. Surfaced as suggestions in the task edit tag field.
  public var knownTagSuggestions: [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for task in allKnownTasks {
      for tag in task.tags where seen.insert(tag.lowercased()).inserted {
        ordered.append(tag)
      }
    }
    return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  /// Candidate tasks for a dependency picker. An empty query lists open tasks;
  /// a non-empty query runs the core text search. `excluding` drops the task
  /// being edited (and any already-selected dependencies) from the results.
  public func dependencyCandidates(
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
      // A dependency-picker lookup is a non-critical type-ahead read; a global
      // error banner on every errored keystroke would be wrong UX, so degrade to
      // an empty result — but log it so the failure isn't silently invisible.
      taskEditLog.error(
        "dependencyCandidates lookup failed: \(error.localizedDescription, privacy: .private)"
      )
      return []
    }
  }

  /// Resolves dependency IDs to their tasks for display in the editor. Prefers
  /// every loaded pool, falling back to a core load for IDs not present there.
  public func dependencyTasks(for ids: [LorvexTask.ID]) async -> [LorvexTask] {
    var resolved: [LorvexTask] = []
    for id in ids {
      if let task = resolveTask(id) {
        resolved.append(task)
      } else if let task = try? await core.loadTask(id: id) {
        resolved.append(task)
        cacheTasks([task])
      }
    }
    return resolved
  }
}
