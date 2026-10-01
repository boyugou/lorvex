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
  /// sheet while the routed detail re-query starts.
  func invalidateTaskViewsAfterCanonicalReload() {
    taskCache.removeAll()
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
