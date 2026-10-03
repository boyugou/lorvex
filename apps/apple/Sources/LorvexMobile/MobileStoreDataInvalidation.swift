extension MobileStore {
  /// Invalidate view-owned task query pages (every scoped task list, a list's
  /// screen included) whose task membership/content may have changed. These
  /// views intentionally own their paginated query state, so assigning the
  /// store's Today snapshot alone cannot refresh them.
  func invalidateTaskViews() {
    taskWorkspaceRevision &+= 1
  }

  /// External/full reloads invalidate the query cache itself as well as the
  /// view keys. This prevents a deleted or peer-edited task that is outside the
  /// small Today snapshot from remaining a source for a newly opened edit
  /// sheet while the routed detail re-query starts. The task whose detail is
  /// open (``selectedTaskID``) keeps its entry, because that detail re-reads it
  /// at once (``refreshTaskForRoute(_:)``), which replaces the copy or evicts
  /// it on a confirmed deletion. Dropping it would swap the open detail for
  /// its skeleton until the read returns, taking down a sheet or composer
  /// over it, and would turn a transient read failure into "Task Not Found".
  func invalidateTaskViewsAfterCanonicalReload() {
    let openTask = selectedTaskID.flatMap { taskCache[$0] }
    taskCache.removeAll()
    if let openTask { taskCache[openTask.id] = openTask }
    invalidateTaskViews()
  }

  func invalidateHabitDetailViews() {
    habitDetailRevision &+= 1
  }

  func invalidateAllViewOwnedData() {
    invalidateTaskViewsAfterCanonicalReload()
    invalidateHabitDetailViews()
  }
}
