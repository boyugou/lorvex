import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Scratch probe (git-excluded): a seeded random walk over AppStore's task
// operations. After every step each surface the store keeps must agree with
// the core. WALK_SEED = RNG seed, WALK_STEPS = operations per walk (default 40).
// Does nothing without WALK_SEED. Prints one `WALK seed=… steps=… failures=…`
// line, then the trace and every failure when there is one.

private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private struct Step {
  var weight: Int
  var name: String
  var grouped = true
  var run: () async -> Void
}

private func day(_ date: Date?) -> String {
  date.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-"
}

private func brief(_ task: LorvexTask) -> String {
  let time = task.plannedTime.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "-"
  return "\(task.id.prefix(6)) \(task.status.rawValue) plan=\(day(task.plannedDate)) time=\(time) "
    + "list=\(task.listID?.prefix(6) ?? "-") \(task.title)"
}

@MainActor
private final class Walk {
  let core: SwiftLorvexCoreService
  let store: AppStore
  var rng: SplitMix64
  let undo = UndoManager()
  var trace: [String] = []
  var failures: [String] = []
  var counter = 0
  var listIDs: [String] = []

  init(seed: UInt64) async throws {
    core = try await makeSeededInMemoryCore()
    store = AppStore(core: core)
    rng = SplitMix64(state: seed)
    undo.groupsByEvent = false
    await store.refresh()
    // What TodayView's `.task` does when the view appears.
    async let schedule: Void = store.loadTodaySchedule()
    async let done: Void = store.loadDoneTodayCount()
    await store.loadWorkdayWindow()
    _ = await schedule
    _ = await done
    lastToday = store.today
    lastGeneration = store.taskDataGeneration
    listIDs = try await core.loadLists().lists.map(\.id)
  }

  /// The Today snapshot the Done section was last reloaded for. TodayView
  /// reloads the Done section whenever `store.today` changes.
  var lastToday: TodaySnapshot = .empty
  var lastGeneration: UInt64 = 0
  var calendarLoaded = false
  var notes: [String] = []

  var stepFailures = 0

  func fail(_ kind: String, _ message: String) {
    stepFailures += 1
    failures.append("\(kind) | step \(trace.count) | \(trace.last ?? "") | \(message)")
  }

  // MARK: Reads

  func allTasks() async -> [LorvexTask] {
    var out: [LorvexTask] = []
    var offset = 0
    while true {
      guard
        let page = try? await core.listTasks(
          status: "all", listID: nil, priority: nil, text: nil, limit: 200, offset: offset)
      else { break }
      out += page.tasks
      guard let next = page.nextOffset else { break }
      offset = next
    }
    return out
  }

  func projection() async -> [String] {
    await allTasks().map(brief).sorted()
  }

  // MARK: Random helpers

  func pick<T>(_ items: [T]) -> T? {
    items.isEmpty ? nil : items[Int(rng.next() % UInt64(items.count))]
  }

  func pickSome<T>(_ items: [T], max: Int) -> [T] {
    guard !items.isEmpty else { return [] }
    let count = 1 + Int(rng.next() % UInt64(min(max, items.count)))
    var pool = items
    var out: [T] = []
    for _ in 0..<count {
      let index = Int(rng.next() % UInt64(pool.count))
      out.append(pool.remove(at: index))
    }
    return out
  }

  func weightedPick(_ steps: [Step]) -> Step? {
    let total = steps.reduce(0) { $0 + $1.weight }
    guard total > 0 else { return nil }
    var roll = Int(rng.next() % UInt64(total))
    for step in steps {
      if roll < step.weight { return step }
      roll -= step.weight
    }
    return steps.last
  }

  // MARK: Steps

  func buildSteps(_ tasks: [LorvexTask]) -> [Step] {
    var steps: [Step] = []
    let active = tasks.filter { $0.status.isActive }
    let actionable = tasks.filter { $0.status.isActionable }
    let resolved = tasks.filter { $0.status.isResolved }
    let someday = tasks.filter { $0.status == .someday }
    let open = tasks.filter { $0.status == .open }
    let started = tasks.filter { $0.status == .inProgress }
    let todayRows = store.todayOrderedTasks

    steps.append(
      Step(weight: 10, name: "create") { [self] in
        counter += 1
        let variants = ["", " tomorrow", " today", " !1", " 30m", " at 3pm"]
        let line = "Walk \(counter)\(variants[Int(rng.next() % UInt64(variants.count))])"
        trace[trace.count - 1] += " '\(line)'"
        await store.captureLine(line)
      })
    if let task = pick(active) {
      steps.append(
        Step(weight: 10, name: "complete \(brief(task))") { [self] in
          await store.completeTask(id: task.id, undoManager: undo)
        })
    }
    if let task = pick(tasks.filter { $0.status != .cancelled && $0.status != .someday }) {
      steps.append(
        Step(weight: 8, name: "toggle \(brief(task))") { [self] in
          await store.toggleTaskCompletion(task, undoManager: undo)
        })
    }
    if let task = pick(tasks.filter { $0.status != .completed && $0.status != .cancelled }) {
      steps.append(
        Step(weight: 6, name: "defer-row \(brief(task))") { [self] in
          await store.deferTaskFromRow(task, until: Date().addingTimeInterval(86_400))
        })
    }
    if let task = pick(todayRows) {
      steps.append(
        Step(weight: 8, name: "select \(brief(task))") { [self] in
          store.selectOnlyTodayTask(task.id)
          await syncInspector()
        })
    }
    if store.selectedTaskID != nil {
      steps.append(
        Step(weight: 3, name: "deselect") { [self] in
          store.selectedTaskID = nil
        })
      if store.selectedTaskCanComplete {
        steps.append(
          Step(weight: 3, name: "complete-selected") { [self] in
            await store.completeSelectedTask(undoManager: undo)
          })
      }
      if store.selectedTaskCanReopen {
        steps.append(
          Step(weight: 5, name: "reopen-selected") { [self] in
            await store.reopenSelectedTask()
          })
      }
      if store.selectedTaskCanStart, let task = store.selectedTask, !store.startIsHeldUp(for: task) {
        steps.append(
          Step(weight: 3, name: "start-selected") { [self] in
            await store.startSelectedTask()
          })
      }
      if store.selectedTaskCanPause {
        steps.append(
          Step(weight: 3, name: "pause-selected") { [self] in
            await store.pauseSelectedTask()
          })
      }
      if store.selectedTaskCanMarkSomeday {
        steps.append(
          Step(weight: 3, name: "someday-selected") { [self] in
            await store.markSelectedTaskSomeday()
          })
      }
      if let task = store.selectedTask, task.status.isActive {
        steps.append(
          Step(weight: 4, name: "cancel-selected \(task.recurrence == nil ? "" : "(recurring)")") {
            [self] in
            if task.recurrence == nil {
              await store.cancelSelectedTask(undoManager: undo)
            } else {
              let scope: RecurringTaskCancelScope = rng.next() % 2 == 0 ? .thisOccurrence : .all
              trace[trace.count - 1] += " scope=\(scope)"
              await store.cancelRecurringTask(id: task.id, scope: scope)
            }
          })
      }
    }
    if let task = store.selectedTask, task.status.isActionable {
      steps.append(
        Step(weight: 3, name: "snooze-selected") { [self] in
          await store.snoozeSelectedTask(until: Date().addingTimeInterval(2 * 86_400))
        })
      steps.append(
        Step(weight: 3, name: "defer-selected") { [self] in
          await store.deferSelectedTask()
        })
      steps.append(
        Step(weight: 3, name: "edit-title") { [self] in
          counter += 1
          store.taskDetailTitle = "Edited \(counter)"
          await store.saveSelectedTaskDraft()
        })
      steps.append(
        Step(weight: 2, name: "edit-estimate") { [self] in
          store.taskDetailEstimatedMinutesText = "\(15 * (1 + Int(rng.next() % 6)))"
          await store.saveSelectedTaskDraft()
        })
      steps.append(
        Step(weight: 2, name: "add-checklist") { [self] in
          counter += 1
          store.taskDetailNewChecklistText = "step \(counter)"
          await store.addChecklistItemToSelectedTask()
        })
      steps.append(
        Step(weight: 2, name: "add-reminder") { [self] in
          await store.addReminderToSelectedTask()
        })
      if let item = task.checklistItems.first {
        steps.append(
          Step(weight: 2, name: "toggle-checklist") { [self] in
            await store.toggleChecklistItem(item)
          })
      }
    }
    if let task = pick(open) {
      steps.append(
        Step(weight: 2, name: "start-row \(brief(task))") { [self] in
          // A row exists only on a loaded surface, where the blocked mark would
          // keep Start from being offered; ask the core directly for a task that
          // no loaded surface shows.
          guard !store.startIsHeldUp(for: task),
            (try? await core.blockedTaskIDs(in: [task]))?.contains(task.id) != true
          else { return }
          await store.startTaskFromRow(task)
        })
    }
    if let task = pick(started) {
      steps.append(
        Step(weight: 2, name: "pause-row \(brief(task))") { [self] in
          await store.pauseTaskFromRow(task)
        })
    }
    if let task = pick(active) {
      steps.append(
        Step(weight: 2, name: "snooze-row \(brief(task))") { [self] in
          await store.snoozeTask(id: task.id, until: Date().addingTimeInterval(3 * 86_400))
        })
    }
    if store.selection == .tasks, store.taskWorkspaceHasLoaded {
      let rows = store.taskWorkspaceAllTasks
      if let task = pick(rows) {
        steps.append(
          Step(weight: 6, name: "ws-select \(brief(task))") { [self] in
            store.selectOnlyTaskInWorkspace(task.id)
            await syncInspector()
          })
      }
      if !rows.isEmpty {
        let ids = pickSome(rows, max: 4).map(\.id)
        let label = ids.map { String($0.prefix(6)) }
        steps.append(
          Step(weight: 4, name: "ws-batch-complete \(label)") { [self] in
            store.setTaskWorkspaceSelection(Set(ids))
            await syncInspector()
            await store.completeTaskWorkspaceSelection(undoManager: undo)
          })
        steps.append(
          Step(weight: 3, name: "ws-batch-defer \(label)") { [self] in
            store.setTaskWorkspaceSelection(Set(ids))
            await syncInspector()
            await store.deferTaskWorkspaceSelection()
          })
        steps.append(
          Step(weight: 3, name: "ws-batch-someday \(label)") { [self] in
            store.setTaskWorkspaceSelection(Set(ids))
            await syncInspector()
            await store.markTaskWorkspaceSelectionSomeday()
          })
        steps.append(
          Step(weight: 4, name: "ws-batch-reopen \(label)") { [self] in
            store.setTaskWorkspaceSelection(Set(ids))
            await syncInspector()
            await store.reopenTaskWorkspaceSelection()
          })
        steps.append(
          Step(weight: 3, name: "ws-batch-cancel \(label)") { [self] in
            store.setTaskWorkspaceSelection(Set(ids))
            await syncInspector()
            await store.cancelTaskWorkspaceSelection()
            if let pending = store.pendingRecurringBatchCancel {
              store.pendingRecurringBatchCancel = nil
              let scope: RecurringTaskCancelScope = rng.next() % 2 == 0 ? .thisOccurrence : .all
              trace[trace.count - 1] += " pending scope=\(scope)"
              await store.cancelBatch(on: .taskWorkspace, recurringScope: scope, pending: pending)
            }
          })
        if let listID = pick(listIDs) {
          steps.append(
            Step(weight: 3, name: "ws-batch-move \(label) -> \(listID.prefix(6))") { [self] in
              store.setTaskWorkspaceSelection(Set(ids))
              await syncInspector()
              await store.moveTaskWorkspaceSelection(toListID: listID, undoManager: undo)
            })
        }
      }
    }
    if !todayRows.isEmpty {
      let ids = pickSome(todayRows.filter { $0.status.isActive }, max: 3).map(\.id)
      if !ids.isEmpty {
        steps.append(
          Step(weight: 2, name: "today-to-tomorrow \(ids.map { String($0.prefix(6)) })") { [self] in
            await store.moveTodayTasksToTomorrow(ids)
          })
      }
    }
    if !actionable.isEmpty {
      let ids = pickSome(actionable, max: 3).map(\.id)
      let days = Int(rng.next() % 5)
      steps.append(
        Step(weight: 6, name: "plan-day ids=\(ids.map { String($0.prefix(6)) }) +\(days)d") {
          [self] in
          await store.planTasks(ids: ids, daysFromToday: days, undoManager: undo)
        })
      let minute = Int(rng.next() % 20) * 30 + 360
      let column = Date().addingTimeInterval(Double(days) * 86_400)
      steps.append(
        Step(
          weight: 6,
          name: "plan-time ids=\(ids.map { String($0.prefix(6)) }) +\(days)d @\(minute)"
        ) { [self] in
          await store.planTasks(ids: ids, on: column, time: .start(minute), undoManager: undo)
        })
    }
    if !todayRows.isEmpty {
      let ids = pickSome(todayRows, max: 4).map(\.id)
      let label = ids.map { String($0.prefix(6)) }
      steps.append(
        Step(weight: 3, name: "batch-complete \(label)") { [self] in
          store.setTodaySelection(Set(ids))
          await syncInspector()
          await store.completeTodaySelection(undoManager: undo)
        })
      steps.append(
        Step(weight: 3, name: "batch-defer \(label)") { [self] in
          store.setTodaySelection(Set(ids))
          await syncInspector()
          await store.deferTodaySelection()
        })
      steps.append(
        Step(weight: 2, name: "batch-someday \(label)") { [self] in
          store.setTodaySelection(Set(ids))
          await syncInspector()
          await store.markTodaySelectionSomeday()
        })
      steps.append(
        Step(weight: 3, name: "batch-reopen \(label)") { [self] in
          store.setTodaySelection(Set(ids))
          await syncInspector()
          await store.reopenTodaySelection()
        })
      steps.append(
        Step(weight: 3, name: "batch-cancel \(label)") { [self] in
          store.setTodaySelection(Set(ids))
          await syncInspector()
          await store.cancelTodaySelection()
          if let pending = store.pendingRecurringBatchCancel {
            store.pendingRecurringBatchCancel = nil
            let scope: RecurringTaskCancelScope = rng.next() % 2 == 0 ? .thisOccurrence : .all
            trace[trace.count - 1] += " pending scope=\(scope)"
            await store.cancelBatch(on: .today, recurringScope: scope, pending: pending)
          }
        })
    }
    if let listID = pick(listIDs), !tasks.isEmpty {
      let ids = pickSome(tasks, max: 3).map(\.id)
      steps.append(
        Step(weight: 4, name: "move \(ids.map { String($0.prefix(6)) }) -> \(listID.prefix(6))") {
          [self] in
          await store.moveTasks(ids: ids, toListID: listID, undoManager: undo)
        })
    }
    if let task = pick(tasks) {
      steps.append(
        Step(weight: 2, name: "permanent-delete \(brief(task))") { [self] in
          store.requestPermanentDelete(task)
          await store.confirmPermanentDelete()
        })
    }
    if undo.canUndo {
      steps.append(
        Step(weight: 8, name: "undo (\(undo.undoActionName))", grouped: false) { [self] in
          undo.undo()
          await settle()
        })
    }
    if undo.canRedo {
      steps.append(
        Step(weight: 4, name: "redo (\(undo.redoActionName))", grouped: false) { [self] in
          undo.redo()
          await settle()
        })
    }
    steps.append(
      Step(weight: 3, name: "refresh") { [self] in
        await store.refresh()
      })
    steps.append(
      Step(weight: 4, name: "open-workspace") { [self] in
        store.selection = .tasks
        await store.loadTaskWorkspace()
      })
    steps.append(
      Step(weight: 3, name: "show-today") { [self] in
        store.selection = .today
      })
    steps.append(
      Step(weight: 3, name: "open-calendar") { [self] in
        store.selection = .calendar
        try? await store.refreshCurrentCalendarTimeline()
        calendarLoaded = true
      })
    if let listID = pick(listIDs) {
      steps.append(
        Step(weight: 2, name: "open-list \(listID.prefix(6))") { [self] in
          store.selection = .lists
          store.selectedListID = listID
          try? await store.loadSelectedListDetail()
        })
    }
    _ = (resolved, someday, open, started)
    return steps
  }

  /// What the inspector does when the selected task changes: it adopts the
  /// task into its draft and loads the task's detail.
  func syncInspector() async {
    store.syncSelectedTaskDraft()
    await store.loadSelectedTaskDetail()
  }

  /// Waits until an undo's or redo's detached write has landed: the task set
  /// stops changing for a few polls.
  func settle() async {
    var previous: [String] = []
    var stable = 0
    for _ in 0..<100 {
      try? await Task.sleep(for: .milliseconds(30))
      let now = await projection()
      if now == previous && !store.isRefreshing { stable += 1 } else { stable = 0 }
      previous = now
      if stable >= 3 { return }
    }
  }

  // MARK: Invariants

  func check() async {
    if let message = store.errorMessage {
      var detail = ""
      if let diagnostics = try? await core.loadRuntimeDiagnostics(),
        let entry = diagnostics.recentLogs.entries.first(where: { $0.source == "error_log" })
      {
        detail = " :: " + String((entry.details ?? entry.summary).prefix(260))
      }
      fail("error", "surfaced: \(message)\(detail)")
    }

    // TodayView reloads the Done section when `today` or the task-data
    // generation changes; a change that moves the Done section while neither
    // changes is reported as a note.
    let todayChangedStrict = store.today != lastToday
    let todayChanged = todayChangedStrict || store.taskDataGeneration != lastGeneration
    lastToday = store.today
    lastGeneration = store.taskDataGeneration
    if todayChanged { await store.loadDoneTodayCount() }

    guard let fresh = try? await core.loadToday() else { return fail("core", "loadToday threw") }
    let shown = store.today
    if shown.tasks.map(brief) != fresh.tasks.map(brief) {
      fail("today-differs", "store \(shown.tasks.map(brief)) core \(fresh.tasks.map(brief))")
    }
    if shown.inProgressTasks.map(brief) != fresh.inProgressTasks.map(brief) {
      fail("today-inprogress", "differs")
    }

    // Today's column shows every active task of the day's pool exactly once.
    let rows = store.todayOrderedTasks.filter { $0.status.isActionable }.map(\.id)
    if Set(rows).count != rows.count { fail("column-dup", "\(rows)") }
    let pool = Set(fresh.tasks.filter { $0.status.isActionable }.map(\.id))
    if Set(rows) != pool {
      fail(
        "column-pool",
        "missing \(pool.subtracting(rows).map { $0.prefix(6) }) extra \(Set(rows).subtracting(pool).map { $0.prefix(6) })"
      )
    }

    // The Done section holds exactly what the core says was finished today.
    if let stats = try? await core.loadWidgetStatsSource() {
      let expected = Set(stats.completedTodayTasks.map(\.id))
      let shownDone = Set(store.doneTodayTasks.map(\.id))
      if expected != shownDone || store.doneTodayCount != expected.count {
        let message =
          "Done section differs (today changed: \(todayChanged)): core \(expected.map { $0.prefix(6) }) store \(shownDone.map { $0.prefix(6) }) count \(store.doneTodayCount)"
        if todayChanged { fail("done", message) } else { notes.append("step \(trace.count): \(message)") }
        await store.loadDoneTodayCount()
      }
    }

    // Today's batch selection only names tasks Today shows.
    let visible = Set(store.todayOrderedTasks.map(\.id))
    let stray = store.todaySelectedTaskIDs.subtracting(visible)
    if !stray.isEmpty { fail("selection-hidden", "\(stray.map { $0.prefix(6) })") }

    // The selected task is real, and the copy the inspector reads is current.
    if let id = store.selectedTaskID {
      if let stored = try? await core.loadTask(id: id) {
        if let shownTask = store.selectedTask {
          if brief(shownTask) != brief(stored) {
            fail("selected-stale", "store \(brief(shownTask)) core \(brief(stored))")
          }
        } else if store.selection == .today || store.selection == .tasks {
          fail("selected-nil", "\(id.prefix(6))")
        }
      } else {
        fail("selected-gone", "\(id.prefix(6))")
      }
    }

    // The walk never leaves typed text unsaved, so the inspector's draft must
    // agree with the record it shows; a draft that disagrees would be saved over
    // the task when the user navigates away.
    if store.selectedTaskID != nil, store.selectedTask != nil, store.selectedTaskHasUnsavedEditorState {
      let record = store.selectedTask
      var diffs: [String] = []
      if let record {
        if store.taskDetailTitle != record.title { diffs.append("title") }
        if store.taskDetailNotes != record.notes { diffs.append("notes") }
        if store.taskDetailPriority != record.priority { diffs.append("priority") }
        if store.parsedTaskDetailEstimate != record.estimatedMinutes { diffs.append("estimate") }
        if store.taskDetailPlannedDateForSave != record.plannedDate { diffs.append("plannedDate draft=\(day(store.taskDetailPlannedDateForSave)) record=\(day(record.plannedDate))") }
        if store.taskDetailPlannedTimeForSave != record.plannedTime { diffs.append("plannedTime") }
        if store.taskDetailDueDateForSave != record.dueDate { diffs.append("due") }
        if store.taskDetailAvailableFromForSave != record.availableFrom { diffs.append("availableFrom") }
        if store.parsedTaskDetailTags != record.tags { diffs.append("tags") }
        if store.parsedTaskDetailDependencies != record.dependsOn { diffs.append("deps") }
        if store.taskDetailRecurrenceDraft.hasChanges { diffs.append("recurrence") }
        if !store.taskDetailNewChecklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { diffs.append("newChecklistText") }
        if record.checklistItems.contains(where: { (store.taskDetailChecklistDrafts[$0.id] ?? $0.text) != $0.text }) { diffs.append("checklistDraft") }
      }
      fail("draft-dirty", "differs in \(diffs) draftTask=\(store.taskDetailDraftTaskID.map { String($0.prefix(6)) } ?? "nil") record \(record.map(brief) ?? "-")")
    }

    // The sidebar's list counts match the catalog.
    if let catalog = try? await core.loadLists(), let shownLists = store.lists {
      let want = catalog.lists.map { "\($0.id.prefix(6)) \($0.openCount)/\($0.completedCount)/\($0.cancelledCount)" }
      let have = shownLists.lists.map { "\($0.id.prefix(6)) \($0.openCount)/\($0.completedCount)/\($0.cancelledCount)" }
      if want != have { fail("lists", "store \(have) core \(want)") }
    }

    // The calendar window equals a fresh read of itself. CalendarWorkspaceView
    // refetches when `today` changes.
    if calendarLoaded, store.selection == .calendar, store.calendarScheduledTasks != nil {
      let viewRefetches = todayChangedStrict
      if viewRefetches { try? await store.refreshCurrentCalendarTimeline() }
      let before = (store.calendarScheduledTasks ?? []).map(brief)
      try? await store.refreshCurrentCalendarTimeline()
      let after = (store.calendarScheduledTasks ?? []).map(brief)
      if before != after {
        let message = "calendar window was stale (view refetched: \(viewRefetches))\n  before \(before)\n  fresh  \(after)"
        if viewRefetches { fail("calendar", message) } else { fail("calendar-stale", message) }
      }
    }

    // The open list's pane equals a fresh read of itself.
    if let detail = store.selectedListDetail, store.selection == .lists,
      let fresh = try? await core.loadListDetail(id: detail.list.id, limit: detail.limit, offset: 0)
    {
      if detail.tasks.map(brief) != fresh.tasks.map(brief) {
        fail("list-detail", "store \(detail.tasks.map(brief)) core \(fresh.tasks.map(brief))")
      }
    }

    // The Tasks workspace equals a fresh load of itself.
    if store.taskWorkspaceHasLoaded {
      let before = workspaceSections()
      await store.loadTaskWorkspace()
      let after = workspaceSections()
      if before != after { fail("workspace", "before \(before) fresh \(after)") }
    }
  }

  func workspaceSections() -> [[String]] {
    store.taskWorkspaceStorage.sections.map { $0.map(brief) }
  }

  // MARK: Walk

  func run(steps count: Int) async {
    for _ in 0..<count {
      let tasks = await allTasks()
      guard let step = weightedPick(buildSteps(tasks)) else { return }
      trace.append(step.name)
      store.errorMessage = nil
      if step.grouped { undo.beginUndoGrouping() }
      await step.run()
      if step.grouped { undo.endUndoGrouping() }
      stepFailures = 0
      await check()
      if stepFailures > 0 {
        // Heal to the store's own ground truth so the next step starts clean.
        await store.refresh()
        await store.loadDoneTodayCount()
        store.todayStorage.selectedTaskIDs = []
        await syncInspector()
        store.syncSelectedTaskDraft(force: true)
        if store.taskWorkspaceHasLoaded { await store.loadTaskWorkspace() }
        lastToday = store.today
      }
    }
  }
}

@MainActor
@Test
func zzRandomWalkProbe() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let seed = env["WALK_SEED"].flatMap(UInt64.init) else { return }
  let steps = env["WALK_STEPS"].flatMap(Int.init) ?? 40
  let walk = try await Walk(seed: seed)
  await walk.run(steps: steps)
  print("WALK seed=\(seed) steps=\(walk.trace.count) failures=\(walk.failures.count) notes=\(walk.notes.count)")
  for note in walk.notes { print("WALK note \(note)") }
  if !walk.failures.isEmpty {
    if env["WALK_TRACE"] != nil {
      for (index, line) in walk.trace.enumerated() { print("WALK trace \(index + 1): \(line)") }
    }
    for failure in walk.failures { print("WALK FAIL seed=\(seed) \(failure)") }
  }
}
