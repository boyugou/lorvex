import Foundation

extension WidgetSnapshot {
  /// This snapshot narrowed to one list: that list's tasks and counts, the
  /// list itself as ``scopeList`` (so the widget can name it), and no
  /// briefing, since the briefing speaks about the whole day and can name
  /// tasks the narrowing removed. A nil `listID` returns the snapshot
  /// unchanged.
  public func scoped(toList listID: String?) -> WidgetSnapshot {
    guard let listID else { return self }
    let listTasks = tasks.filter { $0.listID == listID }
    return WidgetSnapshot(
      version: version,
      generatedAt: generatedAt,
      storageGeneration: storageGeneration,
      focusFilterRevision: focusFilterRevision,
      workspaceInstanceID: workspaceInstanceID,
      localChangeSequence: localChangeSequence,
      timezone: timezone,
      logicalDay: logicalDay,
      stats: listStats.first { $0.id == listID }?.stats
        ?? Stats(
          todayCount: listTasks.count, overdueCount: 0, dueTodayCount: 0,
          completedTodayCount: 0),
      briefing: nil,
      tasks: listTasks,
      habits: habits,
      lists: lists,
      listStats: listStats,
      scopeList: lists.first { $0.id == listID })
  }
}
