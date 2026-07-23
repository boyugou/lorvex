import LorvexCore

extension MobileStore {
  public var canSubmitCapture: Bool {
    captureDraft.canSubmit && !isCapturing
  }

  public var selectedTask: LorvexTask? {
    guard let selectedTaskID else { return nil }
    return resolveTask(selectedTaskID)
  }

  /// Resolve a task by id across every loaded pool — the Today snapshot, the
  /// open list detail, and the focus plan — so a detail route opened from a
  /// list row (whose task isn't in Today) finds it instead of 404ing.
  public func resolveTask(_ id: LorvexTask.ID) -> LorvexTask? {
    if let task = snapshot.inProgressTasks.first(where: { $0.id == id }) { return task }
    if let task = snapshot.today.tasks.first(where: { $0.id == id }) { return task }
    if let task = selectedListDetail?.tasks.first(where: { $0.id == id }) { return task }
    if let task = snapshot.focusTasks.first(where: { $0.id == id }) { return task }
    return taskCache[id]
  }

  public var allKnownTasks: [LorvexTask] {
    var tasksByID: [LorvexTask.ID: LorvexTask] = [:]
    for task in snapshot.inProgressTasks {
      tasksByID[task.id] = task
    }
    for task in snapshot.today.tasks {
      tasksByID[task.id] = task
    }
    for task in selectedListDetail?.tasks ?? [] {
      tasksByID[task.id] = task
    }
    for task in snapshot.focusTasks {
      tasksByID[task.id] = task
    }
    for task in taskCache.values {
      tasksByID[task.id] = task
    }
    return tasksByID.values.sorted {
      if $0.priority != $1.priority { return $0.priority.rawValue < $1.priority.rawValue }
      return $0.id < $1.id
    }
  }

  public func cacheTasks(_ tasks: [LorvexTask]) {
    for task in tasks {
      taskCache[task.id] = task
    }
  }

  func replaceKnownTask(_ task: LorvexTask) {
    cacheTasks([task])
    if let index = snapshot.today.inProgressTasks.firstIndex(where: { $0.id == task.id }) {
      snapshot.today.inProgressTasks[index] = task
    }
    if let index = snapshot.today.tasks.firstIndex(where: { $0.id == task.id }) {
      snapshot.today.tasks[index] = task
    }
    if let index = selectedListDetail?.tasks.firstIndex(where: { $0.id == task.id }) {
      selectedListDetail?.tasks[index] = task
    }
    // Calendar lane membership is planned-first (`planned_date ?? due_date`).
    let actionDate = task.plannedDate ?? task.dueDate
    if let index = calendarScheduledTasks.firstIndex(where: { $0.id == task.id }) {
      if actionDate == nil {
        calendarScheduledTasks.remove(at: index)
      } else {
        calendarScheduledTasks[index] = task
      }
    } else if actionDate != nil {
      calendarScheduledTasks.append(task)
    }
  }
}
