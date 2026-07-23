import LorvexCore

extension MobileStore {
  /// Re-read a routed task even when an older copy is already cached. A route
  /// refresh driven by ``taskWorkspaceRevision`` uses this to adopt peer/MCP
  /// edits; a confirmed deletion evicts every cached copy so the route can move
  /// to its not-found state. Transient failures keep the last-good UI and surface
  /// the error instead of masquerading as a deletion.
  @discardableResult
  public func refreshTaskForRoute(_ id: LorvexTask.ID) async -> Bool {
    do {
      replaceKnownTask(try await core.loadTask(id: id))
      errorMessage = nil
      return true
    } catch let error as LorvexCoreError {
      switch error {
      case .taskNotFound:
        evictKnownTask(id)
        return false
      default:
        await presentUserFacingError(error)
        return resolveTask(id) != nil
      }
    } catch {
      await presentUserFacingError(error)
      return resolveTask(id) != nil
    }
  }

  private func evictKnownTask(_ id: LorvexTask.ID) {
    taskCache[id] = nil
    snapshot.today.inProgressTasks.removeAll { $0.id == id }
    snapshot.today.tasks.removeAll { $0.id == id }
    selectedListDetail?.tasks.removeAll { $0.id == id }
    calendarScheduledTasks.removeAll { $0.id == id }
    if selectedTaskID == id { selectedTaskID = nil }
  }
}
