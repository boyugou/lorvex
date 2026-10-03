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
      // A smart-cut scope (Scheduled / Priority) or a list scope narrows the
      // result in memory beyond what the status query expresses, so the page
      // count reflects the filtered page rather than the raw query total.
      let narrowsInMemory = scope.narrowsInMemory
      let page: MobileTaskWorkspacePage
      if trimmed.isEmpty {
        let result = try await core.listTasks(
          status: status.coreStatus,
          listID: scope.listID,
          priority: nil,
          text: nil,
          limit: limit,
          offset: offset
        )
        let tasks = result.tasks.filter { status.includes($0) && scope.matches($0) }
        page = MobileTaskWorkspacePage(
          tasks: tasks,
          totalMatching: narrowsInMemory ? tasks.count : result.totalMatching,
          nextOffset: result.nextOffset,
          isNarrowed: narrowsInMemory,
          blockedTaskIDs: await blockedTaskIDs(in: tasks)
        )
      } else {
        // searchTasks has no list/smart filter — narrow in memory.
        let result = try await core.searchTasks(
          query: trimmed,
          status: status.coreStatus,
          limit: limit,
          offset: offset
        )
        let tasks = result.tasks.filter { task in
          status.includes(task) && scope.matches(task)
            && (scope.listID == nil || task.listID == scope.listID)
        }
        page = MobileTaskWorkspacePage(
          tasks: tasks,
          totalMatching: narrowsInMemory ? tasks.count : result.totalMatching,
          nextOffset: result.nextOffset,
          isNarrowed: narrowsInMemory,
          blockedTaskIDs: await blockedTaskIDs(in: tasks)
        )
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
