import Foundation
import LorvexCore

/// Fetches a single Tasks-workspace section page from the core reads. Splits the
/// per-section routing (which core query backs each lane, and how search /
/// list-scope narrow it) out of ``AppStore`` workspace load orchestration, which
/// owns the parallel load, bucket assignment, and pagination state.
extension AppStore {
  static let taskWorkspacePageLimit = 500

  func taskWorkspacePage(
    status: TaskWorkspaceSection,
    query: String,
    listID: LorvexList.ID?
  ) async throws
    -> TaskWorkspacePage
  {
    try await taskWorkspacePage(status: status, query: query, listID: listID, offset: 0)
  }

  func taskWorkspacePage(
    status: TaskWorkspaceSection,
    query: String,
    listID: LorvexList.ID?,
    offset: Int
  ) async throws -> TaskWorkspacePage {
    switch status {
    case .scheduled:
      return try await scheduledLanePage(query: query, listID: listID, offset: offset)
    case .deferred:
      return try await deferredLanePage(query: query, listID: listID, offset: offset)
    default:
      return try await statusLanePage(status: status, query: query, listID: listID, offset: offset)
    }
  }

  /// The Scheduled (defer-until / hidden) lane reads its own core query and is
  /// narrowed client-side by the active list scope and search — the core read
  /// takes neither, and hidden tasks are few, so filtering the page here keeps
  /// the lane coherent with the rest of the workspace without a bespoke query.
  private func scheduledLanePage(
    query: String, listID: LorvexList.ID?, offset: Int
  ) async throws -> TaskWorkspacePage {
    let result = try await core.getHiddenScheduledTasks(
      limit: Self.taskWorkspacePageLimit, offset: offset)
    let tasks = result.tasks.filter { task in
      (listID == nil || task.listID == listID)
        && (query.isEmpty || task.matchesSearch(query))
    }
    return TaskWorkspacePage(tasks: tasks, nextOffset: result.nextOffset)
  }

  /// The Deferred lane is defer_count-based, scoped to the active list when one
  /// is selected. Under search it narrows `searchTasks` client-side (searchTasks
  /// has no `deferred` status — it queries `open` — so repeatedly-deferred tasks
  /// are filtered in to match the non-search `get_deferred_tasks` cut); without
  /// search it reads `get_deferred_tasks` directly.
  private func deferredLanePage(
    query: String, listID: LorvexList.ID?, offset: Int
  ) async throws -> TaskWorkspacePage {
    if !query.isEmpty {
      return try await filteredSearchTaskWorkspacePage(
        query: query,
        status: TaskWorkspaceSection.deferred.coreStatusRawValue,
        offset: offset
      ) { task in
        task.deferCount > 0 && (listID == nil || task.listID == listID)
      }
    }
    let result = try await core.getDeferredTasks(
      listID: listID,
      limit: Self.taskWorkspacePageLimit,
      offset: offset
    )
    return TaskWorkspacePage(tasks: result.tasks, nextOffset: result.nextOffset)
  }

  /// A status-backed lane (open / completed / cancelled / someday). A list scope
  /// reads `list_tasks` (with in-query text filtering); otherwise search routes
  /// through `search_tasks` and the unscoped case through `list_tasks`.
  private func statusLanePage(
    status: TaskWorkspaceSection, query: String, listID: LorvexList.ID?, offset: Int
  ) async throws -> TaskWorkspacePage {
    if let listID {
      let result = try await core.listTasks(
        status: status.coreStatusRawValue,
        listID: listID,
        priority: nil,
        text: query.isEmpty ? nil : query,
        limit: Self.taskWorkspacePageLimit,
        offset: offset
      )
      return TaskWorkspacePage(tasks: result.tasks, nextOffset: result.nextOffset)
    }

    if !query.isEmpty {
      let result = try await core.searchTasks(
        query: query,
        status: status.coreStatusRawValue,
        limit: Self.taskWorkspacePageLimit,
        offset: offset
      )
      return TaskWorkspacePage(tasks: result.tasks, nextOffset: result.nextOffset)
    }

    let result = try await core.listTasks(
      status: status.coreStatusRawValue,
      listID: nil,
      priority: nil,
      text: nil,
      limit: Self.taskWorkspacePageLimit,
      offset: offset
    )
    return TaskWorkspacePage(tasks: result.tasks, nextOffset: result.nextOffset)
  }

  private func filteredSearchTaskWorkspacePage(
    query: String,
    status: String,
    offset: Int,
    include taskMatches: (LorvexTask) -> Bool
  ) async throws -> TaskWorkspacePage {
    var cursor: Int? = offset
    var tasks: [LorvexTask] = []
    while let currentOffset = cursor, tasks.count < Self.taskWorkspacePageLimit {
      let rawLimit = max(1, Self.taskWorkspacePageLimit - tasks.count)
      let result = try await core.searchTasks(
        query: query,
        status: status,
        limit: rawLimit,
        offset: currentOffset
      )
      tasks.append(contentsOf: result.tasks.filter(taskMatches))
      cursor = result.nextOffset
      if result.tasks.isEmpty { break }
    }
    return TaskWorkspacePage(
      tasks: tasks,
      nextOffset: tasks.count == Self.taskWorkspacePageLimit ? cursor : nil
    )
  }
}

struct TaskWorkspacePage {
  let tasks: [LorvexTask]
  let nextOffset: Int?
}
