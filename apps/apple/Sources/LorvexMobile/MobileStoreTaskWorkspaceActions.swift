import Foundation
import LorvexCore

extension MobileStore {
  func taskWorkspacePage(
    scope: MobileTasksScope,
    query: String,
    limit: Int = 80,
    offset: Int = 0
  ) async -> MobileTaskWorkspacePage {
    do {
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
      let status = scope.baseStatus
      let priority = scope == .priority ? 1 : nil
      let requiresDate = scope == .scheduled
      let page: MobileTaskWorkspacePage
      if trimmed.isEmpty {
        let result = try await core.listTasks(query: TaskListQueryRequest(
          status: status.coreStatus, listID: scope.listID, priority: priority,
          requiresScheduledDate: requiresDate, limit: limit, offset: offset))
        page = MobileTaskWorkspacePage(tasks: result.tasks, totalMatching: result.totalMatching,
          nextOffset: result.nextOffset, blockedTaskIDs: await blockedTaskIDs(in: result.tasks))
      } else {
        let result = try await core.searchTasks(query: trimmed, status: status.coreStatus,
          listID: scope.listID, priority: priority, requiresScheduledDate: requiresDate,
          limit: limit, offset: offset)
        page = MobileTaskWorkspacePage(tasks: result.tasks, totalMatching: result.totalMatching,
          nextOffset: result.nextOffset, blockedTaskIDs: await blockedTaskIDs(in: result.tasks))
      }
      cacheTasks(page.tasks)
      return page
    } catch {
      await presentUserFacingError(error)
      return .empty
    }
  }

  /// The ids of `tasks` that wait on an unfinished task
  /// (``LorvexTaskServicing/blockedTaskIDs(in:)``), or none when the read
  /// fails: their rows then offer Start, which the core refuses with its
  /// reason, rather than the list failing over a mark.
  func blockedTaskIDs(in tasks: [LorvexTask]) async -> Set<LorvexTask.ID> {
    (try? await core.blockedTaskIDs(in: tasks)) ?? []
  }

  /// Whether the store holds a task in any status. A failed read answers
  /// true: the Tasks home then keeps its collections rather than invite a
  /// first task into a store that may have many.
  func holdsAnyTask() async -> Bool {
    do {
      let result = try await core.listTasks(
        status: "all", listID: nil, priority: nil, text: nil, limit: 1, offset: 0)
      return !result.tasks.isEmpty
    } catch {
      return true
    }
  }
}
