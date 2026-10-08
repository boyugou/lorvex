import LorvexCore

extension MobileStore {
  /// What decides where a task counts in the lists and in the calendar window
  /// beyond its dates: the list it is in and its place among the actionable,
  /// someday, completed, and cancelled tasks. A started task counts as an open
  /// one, as the lists' open counts do.
  struct TaskPlacement: Equatable {
    let listID: LorvexList.ID?
    let status: LorvexTask.Status

    init(_ task: LorvexTask) {
      listID = task.listID
      status = task.status == .inProgress ? .open : task.status
    }
  }

  /// The placements of the tasks among `ids` that the store holds a copy of.
  func taskPlacements(of ids: [LorvexTask.ID]) -> [LorvexTask.ID: TaskPlacement] {
    var placements: [LorvexTask.ID: TaskPlacement] = [:]
    for id in ids {
      if let task = resolveTask(id) { placements[id] = TaskPlacement(task) }
    }
    return placements
  }

  /// Re-reads what a task mutation can change beyond the tasks it names, when
  /// a task among `ids` is placed differently from `before`
  /// (``taskPlacements(of:)`` read ahead of the mutation; a task the store did
  /// not hold then counts as placed differently): the lists, whose counts
  /// follow the tasks in them, and the scheduled tasks of the loaded calendar
  /// window. A mutation that finishes, cancels, or reopens a task reaches
  /// tasks it was not asked about (finishing a repeating task creates its next
  /// occurrence, reopening one cancels it), so the store reads both again from
  /// the core rather than patching them task by task. An edit that leaves each
  /// task where it was reads nothing. A read that fails keeps what the store
  /// holds; the next refresh reads again.
  func reloadSurfacesAfterTaskMutation(
    ifPlacementsChangedFrom before: [LorvexTask.ID: TaskPlacement], of ids: [LorvexTask.ID]
  ) async {
    guard taskPlacements(of: ids) != before else { return }
    if let loaded = try? await core.loadLists() { lists = loaded }
    await reloadCalendarWindowTasks()
  }

  /// Re-reads the scheduled tasks of the window whose events the store holds,
  /// so the pair stays one window's. Does nothing before the calendar has
  /// loaded a window. A load that starts while this read is in flight replaces
  /// it, as it replaces any other load.
  private func reloadCalendarWindowTasks() async {
    guard let timeline = calendarTimeline else { return }
    let token = calendarTimelineLoadToken
    guard
      let tasks = try? await core.getScheduledTasks(
        from: timeline.from, to: timeline.to, limit: CalendarGridModel.windowTaskLimit),
      token == calendarTimelineLoadToken
    else { return }
    calendarScheduledTasks = tasks
  }
}
