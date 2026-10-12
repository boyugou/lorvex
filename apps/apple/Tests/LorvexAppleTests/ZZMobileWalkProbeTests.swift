import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// Scratch probe (git-excluded): a seeded random walk over MobileStore's task
// operations. After every step each surface the store keeps must agree with
// the core, modelling what the iOS views do on their own triggers:
//   * Today's Done section reloads when `snapshot.today` changes;
//   * a task route re-reads its task when `taskWorkspaceRevision` changes;
//   * the calendar window is loaded when the tab opens and is otherwise
//     updated only by the store.
// MOBILE_SEED = RNG seed, MOBILE_STEPS = operations per walk (default 40).
// Does nothing without MOBILE_SEED. Prints one `MWALK seed=… steps=… failures=…`
// line, then notes, and the trace plus every failure when there is one.

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
  var run: () async -> Void
}

private func day(_ date: Date?) -> String {
  date.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-"
}

private func brief(_ task: LorvexTask) -> String {
  let time = task.plannedTime.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "-"
  return "\(task.id.prefix(6)) \(task.status.rawValue) plan=\(day(task.plannedDate)) "
    + "due=\(day(task.dueDate)) time=\(time) list=\(task.listID?.prefix(6) ?? "-") \(task.title)"
}

@MainActor
private final class MobileWalk {
  let core: SwiftLorvexCoreService
  let store: MobileStore
  var rng: SplitMix64
  var trace: [String] = []
  var failures: [String] = []
  var notes: [String] = []
  var counter = 0
  var listIDs: [String] = []
  var lastToday: TodaySnapshot = .empty
  var lastRevision: UInt64 = 0
  var lastProjection: [String] = []
  var calendarLoaded = false
  var detailID: String?
  var stepFailures = 0

  init(seed: UInt64) async throws {
    core = try await makeSeededInMemoryCore()
    store = MobileStore(core: core)
    rng = SplitMix64(state: seed)
    await store.refresh()
    // What the Today page does when it appears.
    await store.loadWorkdayWindow()
    await store.loadDoneTodayCount()
    lastToday = store.snapshot.today
    lastRevision = store.taskWorkspaceRevision
    listIDs = try await core.loadLists().lists.map(\.id)
    lastProjection = await projection()
  }

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

  func label(_ ids: [String]) -> [String] { ids.map { String($0.prefix(6)) } }

  // MARK: Steps

  func buildSteps(_ tasks: [LorvexTask]) -> [Step] {
    var steps: [Step] = []
    let active = tasks.filter { $0.status.isActive }
    let actionable = tasks.filter { $0.status.isActionable }
    let resolved = tasks.filter { $0.status.isResolved }
    let open = tasks.filter { $0.status == .open }
    let started = tasks.filter { $0.status == .inProgress }

    steps.append(
      Step(weight: 8, name: "create") { [self] in
        counter += 1
        let variants = ["", " tomorrow", " today", " !1", " 30m", " at 3pm"]
        let line = "Walk \(counter)\(variants[Int(rng.next() % UInt64(variants.count))])"
        trace[trace.count - 1] += " '\(line)'"
        store.captureDraft = MobileCaptureDraft(title: line)
        await store.submitCaptureDraft()
        await store.refresh()
      })
    if let task = pick(active) {
      steps.append(
        Step(weight: 10, name: "complete \(brief(task))") { [self] in
          await store.completeTask(task.id)
        })
    }
    if let task = pick(tasks.filter { $0.status != .cancelled && $0.status != .someday }) {
      steps.append(
        Step(weight: 6, name: "toggle \(brief(task))") { [self] in
          await store.toggleTaskCompletion(task)
        })
    }
    if let task = pick(resolved) {
      steps.append(
        Step(weight: 4, name: "reopen \(brief(task))") { [self] in
          await store.reopenTask(task.id)
        })
    }
    if let task = pick(active) {
      steps.append(
        Step(weight: 4, name: "cancel \(brief(task)) \(task.recurrence == nil ? "" : "(recurring)")") {
          [self] in
          if MobileTaskActionSection.cancelAsksForScope(task) {
            let scope: RecurringTaskCancelScope = rng.next() % 2 == 0 ? .thisOccurrence : .all
            trace[trace.count - 1] += " scope=\(scope)"
            await store.cancelRecurringTask(id: task.id, scope: scope)
          } else {
            await store.cancelTask(task.id)
          }
        })
    }
    if let task = pick(open) {
      steps.append(
        Step(weight: 3, name: "start \(brief(task))") { [self] in
          guard (try? await core.blockedTaskIDs(in: [task]))?.contains(task.id) != true else {
            return
          }
          await store.startTask(task.id)
        })
    }
    if let task = pick(started) {
      steps.append(
        Step(weight: 3, name: "pause \(brief(task))") { [self] in
          await store.pauseTask(task.id)
        })
    }
    if let task = pick(actionable) {
      steps.append(
        Step(weight: 3, name: "someday \(brief(task))") { [self] in
          await store.markTaskSomeday(task.id)
        })
      let days = 1 + Int(rng.next() % 7)
      steps.append(
        Step(weight: 6, name: "defer \(brief(task)) +\(days)d") { [self] in
          await store.deferTask(task.id, byDays: days)
        })
      let planDays = Int(rng.next() % 6)
      steps.append(
        Step(weight: 5, name: "plan \(brief(task)) +\(planDays)d") { [self] in
          await store.planTask(task.id, on: Date().addingTimeInterval(Double(planDays) * 86_400))
        })
      steps.append(
        Step(weight: 3, name: "edit-title \(brief(task))") { [self] in
          counter += 1
          var draft = MobileTaskEditDraft(task: task)
          draft.title = "Edited \(counter)"
          _ = await store.saveTaskEditDraft(draft)
        })
      steps.append(
        Step(weight: 2, name: "add-checklist \(brief(task))") { [self] in
          counter += 1
          _ = await store.addChecklistItem(taskID: task.id, text: "step \(counter)")
        })
      steps.append(
        Step(weight: 2, name: "add-reminder \(brief(task))") { [self] in
          let hours = 2 + Int(rng.next() % 48)
          _ = await store.addReminder(
            taskID: task.id, date: Date().addingTimeInterval(Double(hours) * 3600))
        })
    }
    if let task = pick(tasks.filter { !$0.checklistItems.isEmpty }),
      let item = task.checklistItems.first
    {
      steps.append(
        Step(weight: 2, name: "toggle-checklist \(brief(task))") { [self] in
          await store.toggleChecklistItem(item)
        })
    }
    if let task = pick(tasks.filter { !$0.reminders.isEmpty }), let reminder = task.reminders.first {
      steps.append(
        Step(weight: 2, name: "remove-reminder \(brief(task))") { [self] in
          _ = await store.removeReminder(taskID: task.id, reminder: reminder)
        })
    }
    if !actionable.isEmpty {
      let ids = pickSome(actionable, max: 4).map(\.id)
      steps.append(
        Step(weight: 4, name: "batch-complete \(label(ids))") { [self] in
          await store.completeTasks(ids)
        })
      steps.append(
        Step(weight: 4, name: "batch-defer-tomorrow \(label(ids))") { [self] in
          await store.deferTasksToTomorrow(ids)
        })
    }
    if !resolved.isEmpty {
      let ids = pickSome(resolved, max: 3).map(\.id)
      steps.append(
        Step(weight: 3, name: "batch-reopen \(label(ids))") { [self] in
          await store.reopenTasks(ids)
        })
    }
    if let listID = pick(listIDs), !tasks.isEmpty {
      let ids = pickSome(tasks, max: 3).map(\.id)
      steps.append(
        Step(weight: 3, name: "batch-move \(label(ids)) -> \(listID.prefix(6))") { [self] in
          await store.moveTasks(ids, toListID: listID)
        })
    }
    if let task = pick(tasks) {
      steps.append(
        Step(weight: 6, name: "open-detail \(brief(task))") { [self] in
          detailID = task.id
          store.cacheTasks([task])
          store.selectedTaskID = task.id
          await store.refreshTaskForRoute(task.id)
        })
    }
    if detailID != nil {
      steps.append(
        Step(weight: 2, name: "close-detail") { [self] in
          detailID = nil
        })
    }
    if let task = pick(tasks) {
      // An assistant or another device edits through the core; the store learns
      // of it through the database-change observer, which runs a full refresh.
      steps.append(
        Step(weight: 4, name: "assistant-edit \(brief(task))") { [self] in
          if task.status.isActionable, rng.next() % 2 == 0 {
            _ = try? await core.updateTask(TaskUpdateDraft(id: task.id, priority: .p1))
          } else if task.status.isActionable {
            _ = try? await core.deferTask(id: task.id, until: Date().addingTimeInterval(4 * 86_400))
          } else {
            _ = try? await core.reopenTask(id: task.id)
          }
          await store.refresh()
        })
    }
    steps.append(
      Step(weight: 3, name: "refresh") { [self] in
        await store.refresh()
      })
    steps.append(
      Step(weight: 4, name: "open-calendar") { [self] in
        await store.refreshCalendarTimeline(around: Date())
        calendarLoaded = true
      })
    steps.append(
      Step(weight: 3, name: "show-today") { [self] in
        await store.loadWorkdayWindow()
        await store.loadDoneTodayCount()
      })
    let scopes: [MobileTasksScope] =
      [.all, .scheduled, .priority, .someday, .completed, .cancelled]
      + listIDs.prefix(2).map { MobileTasksScope.list($0) }
    if let scope = pick(scopes) {
      steps.append(
        Step(weight: 4, name: "open-tasks-page \(scope)") { [self] in
          _ = await store.taskWorkspacePage(scope: scope, query: "")
        })
    }
    return steps
  }

  // MARK: Invariants

  func check(projectionBefore: [String]) async {
    if let message = store.errorMessage {
      var detail = ""
      if let diagnostics = try? await core.loadRuntimeDiagnostics(),
        let entry = diagnostics.recentLogs.entries.first(where: { $0.source == "error_log" })
      {
        detail = " :: " + String((entry.details ?? entry.summary).prefix(260))
      }
      fail("error", "surfaced: \(message)\(detail)")
    }

    // Every change to a task must advance the revision the views re-query on.
    let projectionNow = await projection()
    let revisionAdvanced = store.taskWorkspaceRevision != lastRevision
    if projectionNow != projectionBefore, !revisionAdvanced {
      fail("revision-not-bumped", "the task set changed but taskWorkspaceRevision did not")
    }
    lastRevision = store.taskWorkspaceRevision
    lastProjection = projectionNow

    // The Today page reloads its Done section when the snapshot changes.
    let todayChanged = store.snapshot.today != lastToday
    lastToday = store.snapshot.today
    if todayChanged { await store.loadDoneTodayCount() }

    guard let fresh = try? await core.loadToday() else { return fail("core", "loadToday threw") }
    let shown = store.snapshot.today
    if shown.tasks.map(brief) != fresh.tasks.map(brief) {
      fail("today-differs", "store \(shown.tasks.map(brief)) core \(fresh.tasks.map(brief))")
    }
    if shown.inProgressTasks.map(brief) != fresh.inProgressTasks.map(brief) {
      fail("today-inprogress", "differs")
    }

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

    // An open task route re-reads its task when the revision moves.
    if let id = detailID {
      if revisionAdvanced { await store.refreshTaskForRoute(id) }
      if let stored = try? await core.loadTask(id: id) {
        if let shownTask = store.resolveTask(id) {
          if brief(shownTask) != brief(stored) {
            fail("detail-stale", "store \(brief(shownTask)) core \(brief(stored))")
          }
        } else {
          fail("detail-nil", "\(id.prefix(6))")
        }
      } else if store.resolveTask(id) != nil {
        fail("detail-ghost", "\(id.prefix(6)) is gone from the core but the store still resolves it")
      }
    }

    // The calendar window equals a fresh read of itself.
    if calendarLoaded, let window = store.calendarWindowToReload,
      let freshScheduled = try? await core.getScheduledTasks(
        from: window.from, to: window.to, limit: CalendarGridModel.windowTaskLimit)
    {
      let have = store.calendarScheduledTasks.map(brief).sorted()
      let want = freshScheduled.map(brief).sorted()
      if have != want {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("calendar-stale", "missing \(missing) extra \(extra)")
        await store.refreshCalendarTimeline(from: window.from, to: window.to)
      }
    }

    // The list catalog's counts match the core.
    if let catalog = try? await core.loadLists(), let shownLists = store.lists {
      let want = catalog.lists.map { "\($0.id.prefix(6)) \($0.openCount)/\($0.completedCount)/\($0.cancelledCount)" }
      let have = shownLists.lists.map { "\($0.id.prefix(6)) \($0.openCount)/\($0.completedCount)/\($0.cancelledCount)" }
      if want != have { notes.append("step \(trace.count): lists differ store \(have) core \(want)") }
    }

    // A cached task that differs from the core is only noted: the routes
    // re-read before showing one.
    for (id, cached) in store.taskCache {
      if let stored = try? await core.loadTask(id: id), brief(cached) != brief(stored) {
        notes.append("step \(trace.count): cache differs store \(brief(cached)) core \(brief(stored))")
        break
      }
    }
  }

  // MARK: Walk

  func run(steps count: Int) async {
    for _ in 0..<count {
      let tasks = await allTasks()
      guard let step = weightedPick(buildSteps(tasks)) else { return }
      trace.append(step.name)
      store.errorMessage = nil
      let before = lastProjection
      await step.run()
      stepFailures = 0
      await check(projectionBefore: before)
      if stepFailures > 0 {
        // Heal to the store's own ground truth so the next step starts clean.
        await store.refresh()
        await store.loadDoneTodayCount()
        lastToday = store.snapshot.today
        lastRevision = store.taskWorkspaceRevision
        lastProjection = await projection()
      }
    }
  }
}

@MainActor
@Test
func zzMobileWalkProbe() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let seed = env["MOBILE_SEED"].flatMap(UInt64.init) else { return }
  let steps = env["MOBILE_STEPS"].flatMap(Int.init) ?? 40
  let walk = try await MobileWalk(seed: seed)
  await walk.run(steps: steps)
  print("MWALK seed=\(seed) steps=\(walk.trace.count) failures=\(walk.failures.count) notes=\(walk.notes.count)")
  for note in walk.notes.prefix(12) { print("MWALK note \(note)") }
  if !walk.failures.isEmpty {
    if env["MOBILE_TRACE"] != nil {
      for (index, line) in walk.trace.enumerated() { print("MWALK trace \(index + 1): \(line)") }
    }
    for failure in walk.failures { print("MWALK FAIL seed=\(seed) \(failure)") }
  }
}
