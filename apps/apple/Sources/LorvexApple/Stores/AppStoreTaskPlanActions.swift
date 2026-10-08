import Foundation
import LorvexCore

/// A task's planned day and the time on it, as stored. A plan change records
/// the plans it replaced so ⌘Z can put them back.
struct TaskPlanSnapshot: Equatable, Sendable {
  let id: LorvexTask.ID
  /// The stored planned day (a UTC-midnight anchor), or nil for none.
  let plannedDate: Date?
  /// The task's time on its planned day, in minutes since midnight, or nil for
  /// none. A time never exists without a planned day.
  let plannedTime: Range<Int>?
}

/// What a plan change does with the time of day on the new day.
enum TaskPlanTime: Equatable, Sendable {
  /// The task is planned for the day only; one that had a time gives it up.
  case dayOnly
  /// The task starts at this minute since midnight and keeps its own length
  /// (its time, else its estimate, else half an hour).
  case start(Int)
  /// The task keeps its own time on the new day, and has none if it had none.
  case unchanged
  /// The task takes exactly this time, in minutes since midnight, whatever
  /// length it had. A time reaching outside the day is cut to the day's bounds.
  case exactly(Range<Int>)
}

extension AppStore {
  /// "Plan Task": the name of the Edit menu's undo and redo item for a change
  /// to a task's day or time.
  static var planTaskTitle: String {
    String(
      localized: "task.action.plan_task", defaultValue: "Plan Task",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Plans `ids` on `day` with the time of day `time` says. Every calendar
  /// gesture that places a task goes through here: dropping tasks on a day's
  /// all-day strip, on a time in a day column, or on a month cell, dragging a
  /// timed block to another time or day or by one of its edges, and the pills'
  /// Plan a Day Later items.
  ///
  /// `day` is any instant of the displayed day. With ``TaskPlanTime/start(_:)``
  /// several tasks are stacked one after another from that minute, in the order
  /// given. A task that is finished or cancelled, one that no longer exists,
  /// and one already planned exactly so are left alone, and a drop that leaves
  /// nothing to change writes nothing.
  ///
  /// A change reloads Today, the calendar window, the lists, the Tasks
  /// workspace, and the selected task's detail, and registers its inverse with
  /// `undoManager` so ⌘Z restores every task's previous day and time; the undo
  /// is itself redoable.
  func planTasks(
    ids: [LorvexTask.ID], on day: Date, time: TaskPlanTime, undoManager: UndoManager? = nil
  ) async {
    await planTasks(
      ids: ids, onStorageDate: PlannedDayBridge.storageDate(forLocalInstant: day), time: time,
      undoManager: undoManager)
  }

  /// Plans `ids` on the product day `days` after today (0 is today), each task
  /// keeping its own time of day. This is the menu form of dropping a task on a
  /// month cell, for a pointer or a keyboard that cannot drag: the day counts
  /// from the product's logical today, so it follows the configured day start
  /// and time zone. It registers the same undo as a drag.
  func planTasks(ids: [LorvexTask.ID], daysFromToday days: Int, undoManager: UndoManager? = nil) async {
    guard let plannedDate = try? storageDate(daysFromLogicalToday: days) else { return }
    await planTasks(ids: ids, onStorageDate: plannedDate, time: .unchanged, undoManager: undoManager)
  }

  /// The shared body of every placement: `plannedDate` is already a storage-frame
  /// day (midnight UTC of the calendar day).
  private func planTasks(
    ids: [LorvexTask.ID], onStorageDate plannedDate: Date, time: TaskPlanTime,
    undoManager: UndoManager?
  ) async {
    var seen = Set<LorvexTask.ID>()
    let ids = ids.filter { seen.insert($0).inserted }
    guard !ids.isEmpty else { return }
    await perform {
      var before: [TaskPlanSnapshot] = []
      var after: [TaskPlanSnapshot] = []
      var cursor: Int? = nil
      for id in ids {
        guard let task = try? await core.loadTask(id: id), task.status.isActionable else { continue }
        let planned: Range<Int>?
        switch time {
        case .dayOnly:
          planned = nil
        case .unchanged:
          planned = task.plannedTime
        case .start(let startMinute):
          let range = task.time(startingAt: cursor ?? startMinute)
          cursor = range.upperBound
          planned = range
        case .exactly(let range):
          let start = max(0, range.lowerBound)
          let end = min(24 * 60, range.upperBound)
          guard start < end else { continue }
          planned = start..<end
        }
        let target = TaskPlanSnapshot(id: id, plannedDate: plannedDate, plannedTime: planned)
        let current = TaskPlanSnapshot(
          id: id, plannedDate: task.plannedDate, plannedTime: task.plannedTime)
        guard target != current else { continue }
        before.append(current)
        after.append(target)
      }
      guard !after.isEmpty else { return }
      try await applyPlans(after)
      registerPlanUndo(undo: before, redo: after, undoManager: undoManager)
    }
  }

  /// Registers `undo` as the manager's next undo and `redo` as what undoing
  /// re-registers, so ⌘Z and ⇧⌘Z restore the plans back and forth. The handler
  /// registers the opposite pair synchronously, while the manager is still
  /// undoing, which is what makes it a redo rather than a new undo; the writes
  /// run afterwards on the main actor.
  private func registerPlanUndo(
    undo: [TaskPlanSnapshot], redo: [TaskPlanSnapshot], undoManager: UndoManager?
  ) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { store in
      MainActor.assumeIsolated {
        store.registerPlanUndo(undo: redo, redo: undo, undoManager: undoManager)
        Task { @MainActor in await store.perform { try await store.applyPlans(undo) } }
      }
    }
    undoManager.setActionName(Self.planTaskTitle)
  }

  /// Writes each snapshot's day and time to its task and reloads what shows the
  /// tasks. The selected task's detail adopts the new plan unless it holds
  /// edits that are not saved yet.
  private func applyPlans(_ plans: [TaskPlanSnapshot]) async throws {
    let detailWasClean = !selectedTaskHasUnsavedEditorState
    var updated: [LorvexTask] = []
    for plan in plans {
      updated.append(
        try await core.updateTask(
          TaskUpdateDraft(
            id: plan.id,
            plannedDate: plan.plannedDate.map { .set($0) } ?? .clear,
            plannedTime: plan.plannedTime.map { .set($0) } ?? .clear)))
    }
    for task in updated { replaceTask(task) }
    if let selectedID = selectedTaskID, detailWasClean, plans.contains(where: { $0.id == selectedID }) {
      syncSelectedTaskDraft(force: true)
    }
    today = try await core.loadToday()
    try await refreshCurrentCalendarTimeline()
    try await afterSelectedTaskMutation()
  }
}
