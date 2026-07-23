import LorvexCore

extension AppStore {
  /// Complete a task straight from the menu-bar quick panel, refreshing the
  /// surfaces the panel and the rest of the app read from.
  func menuBarCompleteTask(_ task: LorvexTask) async {
    await perform {
      today = try await core.completeTask(id: task.id)
      try await refreshListSurfaces()
      await reloadTaskWorkspaceIfLoaded()
      await republishSurfacesAfterLocalMutation()
    }
  }
}
