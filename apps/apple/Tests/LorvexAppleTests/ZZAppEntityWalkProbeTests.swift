import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

// Scratch probe (git-excluded): a seeded random walk over AppStore's habit,
// list, memory and calendar-event operations, plus assistant-style edits made
// straight through the core and followed by a full refresh, and peer-style edits
// followed by the selective inbound reload. After every step each surface the
// store keeps must agree with the core, modelling what the Mac views do on
// their own triggers:
//   * the Habits workspace loads the habit stats and the archived list when it
//     appears;
//   * the habit inspector loads its detail when its habit changes;
//   * the Lists workspace loads the selected list's detail when it appears;
//   * the Memory workspace loads the memory when it appears;
//   * the Calendar workspace loads its visible period when it appears, when the
//     period (mode or anchor) changes, and when the Today snapshot changes;
//   * Today loads the day's schedule when it appears.
// AENTITY_SEED = RNG seed, AENTITY_STEPS = operations per walk (default 60).
// Does nothing without AENTITY_SEED. Prints one `AWALK seed=… steps=… failures=…`
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

private func habitBrief(_ h: LorvexHabit) -> String {
  let milestone =
    h.milestone.map {
      "\($0.metric):\($0.value):\($0.currentMilestone.map(String.init) ?? "-"):\($0.nextMilestone)"
    } ?? "-"
  let weekdays = h.weekdays.map { $0.map(String.init).joined() } ?? "-"
  return "\(h.id.prefix(6)) '\(h.name)' arch=\(h.archived) tgt=\(h.targetCount) "
    + "today=\(h.completionsToday) total=\(h.totalCompletions) pos=\(h.position) "
    + "f=\(h.frequencyType) wd=\(weekdays) ppt=\(h.perPeriodTarget.map(String.init) ?? "-") "
    + "dom=\(h.dayOfMonth.map(String.init) ?? "-") mt=\(h.milestoneTarget.map(String.init) ?? "-") "
    + "met=\(h.periodMetDays) rate=\(String(format: "%.3f", h.completionRate30d)) "
    + "cue=\(h.cue ?? "-") icon=\(h.icon ?? "-") color=\(h.color ?? "-") ms=\(milestone)"
}

private func archivedBrief(_ h: LorvexHabit) -> String {
  "\(h.id.prefix(6)) '\(h.name)' icon=\(h.icon ?? "-")"
}

private func listBrief(_ l: LorvexList) -> String {
  "\(l.id.prefix(6)) '\(l.name)' desc=\(l.description ?? "-") color=\(l.color ?? "-") "
    + "icon=\(l.icon ?? "-") \(l.openCount)/\(l.completedCount)/\(l.cancelledCount)/\(l.totalCount) "
    + "arch=\(l.archivedAt ?? "-") pos=\(l.position)"
}

/// An archived list without its task counts: a task change reloads the active lists
/// at once and the archived ones with the loop-back refresh of the write.
private func archivedListBrief(_ l: LorvexList) -> String {
  "\(l.id.prefix(6)) '\(l.name)' desc=\(l.description ?? "-") color=\(l.color ?? "-") "
    + "icon=\(l.icon ?? "-") arch=\(l.archivedAt ?? "-") pos=\(l.position)"
}

private func memoryBrief(_ e: MemoryEntry) -> String { "'\(e.key)'=\(e.content.prefix(24))" }

private func eventBrief(_ e: CalendarTimelineEvent) -> String {
  "\(e.id.prefix(8)) '\(e.title)' \(e.startDate) \(e.startTime ?? "-") -> "
    + "\(e.endDate ?? "-") \(e.endTime ?? "-") allDay=\(e.allDay) loc=\(e.location ?? "-") "
    + "notes=\(e.notes ?? "-")"
}

private func reviewBrief(_ r: DailyReviewEntry?) -> String {
  guard let r else { return "nil" }
  return "\(r.date) s='\(r.summary)' mood=\(r.mood.map(String.init) ?? "-") "
    + "energy=\(r.energyLevel.map(String.init) ?? "-") w=\(r.wins ?? "-") b=\(r.blockers ?? "-") "
    + "l=\(r.learnings ?? "-")"
}

private func evidenceBrief(_ s: DayReviewSummary?) -> String {
  guard let s else { return "nil" }
  return "\(s.date) done=\(s.completedCount) created=\(s.createdCount) dueOpen=\(s.dueOpenCount) "
    + "habits=\(s.habitsCompleted)/\(s.habitsTotal) events=\(s.eventCount) "
    + "top=\(s.topCompleted.map { $0.id.prefix(4) }) open=\(s.dueOpenTasks.map { $0.id.prefix(4) })"
}

private func weekBrief(_ w: WeeklyReviewSnapshot?) -> String {
  guard let w else { return "nil" }
  return "\(w.windowTitle) done=\(w.completedThisWeek) created=\(w.createdThisWeek) "
    + "overdue=\(w.overdueOpen) deferred=\(w.deferredOpen) someday=\(w.someday)"
}

private func scheduledBrief(_ t: LorvexTask) -> String {
  let time = t.plannedTime.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "-"
  let day = t.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-"
  return "\(t.id.prefix(6)) \(t.status.rawValue) plan=\(day) time=\(time) \(t.title)"
}

@MainActor
private final class AppEntityWalk {
  let core: SwiftLorvexCoreService
  let store: AppStore
  var rng: SplitMix64
  var trace: [String] = []
  var failures: [String] = []
  var notes: [String] = []
  var counter = 0
  var stepFailures = 0
  var coverage: [String: Int] = [:]
  let sabotage: String
  /// With AENTITY_LOOPBACK set, a step that wrote through the store is followed by
  /// the full refresh the app's own committed-write signal starts about 50 ms
  /// later, so only gaps that refresh cannot close are reported.
  let loopback = ProcessInfo.processInfo.environment["AENTITY_LOOPBACK"] != nil

  /// The workspaces whose `.task` ran, so a transition into a workspace runs its
  /// appear work exactly once.
  var openedHabits = false
  var openedLists = false
  var openedMemory = false
  var openedCalendar = false
  var openedToday = false
  var inspectorHabitID: String?
  /// The Calendar workspace's own state: the mode and anchor day it shows, the
  /// period it last fetched, and the Today snapshot it last saw.
  var calendarMode: CalendarPresentationMode = .week
  var calendarAnchor = Date()
  var lastFetchedPeriod: CalendarVisiblePeriod?
  var lastSeenToday: TodaySnapshot?
  /// The Reviews workspace's own state: the scope it shows (a fresh appearance
  /// starts on the day page) and whether its Week scope loaded the digest.
  var openedReviews = false
  var reviewMode: ReviewMode = .daily
  var openedReviewWeek = false
  /// What the editor's fields must hold after the step that just ran, when the
  /// step pins them: unchanged after an autosave, the loaded entry's text after a
  /// day switch.
  var expectedDraft: DailyReviewDraftValues?

  init(seed: UInt64, sabotage: String) async throws {
    self.sabotage = sabotage
    core = try await makeSeededInMemoryCore()
    store = AppStore(core: core)
    rng = SplitMix64(state: seed)
    await store.refresh()
  }

  func fail(_ kind: String, _ message: String) {
    stepFailures += 1
    failures.append("\(kind) | step \(trace.count) | \(trace.last ?? "") | \(message)")
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

  /// True for a step that commits a change through a store method, which the
  /// app's own committed-write signal follows with a full refresh. Navigation,
  /// typing, assistant and peer steps are excluded: the last two reload by
  /// themselves.
  func writesThroughStore(_ name: String) -> Bool {
    let quiet = [
      "open-", "select-", "deselect-", "calendar-", "review-scope-", "step-review-",
      "review-jump-", "review-back-", "review-week-of", "review-digest-open-day",
      "type-review", "refresh", "peer-", "assistant-", "edit-memory", "new-memory",
    ]
    return !quiet.contains { name.hasPrefix($0) }
  }

  /// The refresh after a flush that wrote: the store saves a dirty review draft
  /// before it leaves the day or the page, and that commit is a write like any other.
  func loopbackAfterFlush(wasDirty: Bool) async {
    if loopback, wasDirty { await store.refresh() }
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

  func chance(_ n: UInt64) -> Bool { rng.next() % n == 0 }

  /// The editor's fields once they were replaced by the loaded review (empty for
  /// a day with no entry).
  func loadedDraftValues() -> DailyReviewDraftValues {
    let review = store.dailyReview
    return DailyReviewDraftValues(
      summary: review?.summary ?? "", wins: review?.wins ?? "", blockers: review?.blockers ?? "",
      learnings: review?.learnings ?? "", mood: review?.mood, energy: review?.energyLevel)
  }

  func daysAgo(_ k: Int) -> String {
    let today = store.logicalTodayDateString
    return LorvexDateFormatters.ymdUTCAddingDays(today, days: -k) ?? today
  }

  func coreHabits() async -> [LorvexHabit] {
    (try? await core.loadHabits(date: store.logicalTodayDateString))?.habits ?? []
  }

  func coreArchivedHabits() async -> [LorvexHabit] {
    (try? await core.loadArchivedHabits(date: store.logicalTodayDateString))?.habits ?? []
  }

  /// A change another device made: the core already holds it, and the store learns
  /// of it through the selective reload of the domains the applied kinds map to.
  func inbound(_ kinds: Set<EntityKind>) async {
    if let domains = InboundReloadScope.domains(for: kinds) {
      await store.performSelectiveInboundReload(domains)
    } else {
      await store.refresh()
    }
  }

  // MARK: Steps

  func buildSteps() async -> [Step] {
    var steps: [Step] = []
    let active = store.orderedHabits
    let archived = store.archivedHabits
    let lists = store.lists?.lists ?? []
    let entries = store.memoryEntries
    let coreActive = await coreHabits()
    let coreArchived = await coreArchivedHabits()
    let coreLists = (try? await core.loadLists())?.lists ?? []
    let coreEntries = (try? await core.loadMemory())?.entries ?? []

    // MARK: workspaces

    // While the Reviews page is open the walk stays on it longer, so its steps get
    // more of the run.
    let leave = store.selection == .reviews ? 4 : 1
    steps.append(
      Step(weight: max(1, (store.selection == .habits ? 1 : 4) / leave), name: "open-habits") { [self] in
        store.selection = .habits
      })
    steps.append(
      Step(weight: max(1, (store.selection == .lists ? 1 : 3) / leave), name: "open-lists") { [self] in
        store.selection = .lists
      })
    steps.append(
      Step(weight: max(1, (store.selection == .memory ? 1 : 3) / leave), name: "open-memory") { [self] in
        store.selection = .memory
      })
    steps.append(
      Step(weight: max(1, (store.selection == .calendar ? 1 : 4) / leave), name: "open-calendar") { [self] in
        store.selection = .calendar
      })
    steps.append(
      Step(weight: max(1, 2 / leave), name: "open-today") { [self] in store.selection = .today })

    // MARK: habits through the store

    steps.append(
      Step(weight: 6, name: "create-habit") { [self] in
        counter += 1
        store.beginCreateHabitDraft()
        store.draftHabitName = "Habit \(counter)"
        store.draftHabitTargetCountText = ["1", "1", "2", "3"][Int(rng.next() % 4)]
        switch rng.next() % 4 {
        case 0: store.draftHabitCadenceMode = .daily
        case 1:
          store.draftHabitCadenceMode = .weekly
          store.draftHabitWeekdays = [0, 2, 4]
        case 2:
          store.draftHabitCadenceMode = .timesPerWeek
          store.draftHabitTimesPerWeek = 3
        default:
          store.draftHabitCadenceMode = .monthly
          store.draftHabitDayOfMonth = 15
        }
        if chance(3) { store.draftHabitMilestoneTargetText = "5" }
        trace[trace.count - 1] += " \(store.draftHabitCadenceMode)"
        await store.createDraftHabit()
      })
    if let h = pick(active) {
      steps.append(
        Step(weight: 10, name: "complete-habit \(habitBrief(h))") { [self] in
          await store.completeHabit(h)
        })
      steps.append(
        Step(weight: 4, name: "uncomplete-habit \(habitBrief(h))") { [self] in
          await store.uncompleteHabit(h)
        })
      steps.append(
        Step(weight: 4, name: "adjust-habit \(habitBrief(h))") { [self] in
          await store.adjustHabitCompletion(h, delta: chance(2) ? 1 : -1)
        })
      let k = Int(rng.next() % 5)
      steps.append(
        Step(weight: 4, name: "check-in \(habitBrief(h)) \(k)d ago") { [self] in
          await store.checkInHabit(h, on: daysAgo(k))
        })
      steps.append(
        Step(weight: 3, name: "update-habit \(habitBrief(h))") { [self] in
          counter += 1
          await store.updateHabitFields(
            h, name: "Renamed \(counter)",
            targetCount: chance(2) ? 1 + Int(rng.next() % 3) : nil)
        })
      steps.append(
        Step(weight: 3, name: "archive-habit \(habitBrief(h))") { [self] in
          await store.setHabitArchived(h, archived: true)
        })
      steps.append(
        Step(weight: 2, name: "delete-habit \(habitBrief(h))") { [self] in
          await store.deleteHabit(h)
        })
      steps.append(
        Step(weight: 5, name: "select-habit \(habitBrief(h))") { [self] in
          store.selection = .habits
          store.selectedHabitID = h.id
          inspectorHabitID = h.id
          await store.loadHabitDetail(id: h.id)
        })
    }
    if let h = pick(archived) {
      steps.append(
        Step(weight: 4, name: "restore-habit \(habitBrief(h))") { [self] in
          await store.setHabitArchived(h, archived: false)
        })
      steps.append(
        Step(weight: 1, name: "delete-archived-habit \(habitBrief(h))") { [self] in
          await store.deleteHabit(h)
        })
    }
    if store.selectedHabitID != nil {
      steps.append(
        Step(weight: 2, name: "deselect-habit") { [self] in
          store.selectedHabitID = nil
          inspectorHabitID = nil
        })
    }
    if let id = store.selectedHabitID, active.contains(where: { $0.id == id }) {
      steps.append(
        Step(weight: 3, name: "add-habit-reminder \(id.prefix(6))") { [self] in
          counter += 1
          await store.addHabitReminder(
            habitID: id, time: String(format: "%02d:%02d", 6 + counter % 14, (counter % 4) * 15))
        })
      if let policy = store.habitDetail(for: id)?.reminderPolicies.first {
        steps.append(
          Step(weight: 2, name: "toggle-habit-reminder \(id.prefix(6))") { [self] in
            await store.toggleHabitReminderEnabled(policy: policy)
          })
        steps.append(
          Step(weight: 2, name: "remove-habit-reminder \(id.prefix(6))") { [self] in
            await store.removeHabitReminder(habitID: id, policyID: policy.id)
          })
      }
    }

    // MARK: habits through the assistant and a peer

    steps.append(
      Step(weight: 3, name: "assistant-create-habit") { [self] in
        counter += 1
        _ = try? await core.createHabit(
          name: "Assistant habit \(counter)", cue: nil, icon: nil, color: nil, targetCount: 1,
          cadence: .daily, milestoneTarget: nil)
        await store.refresh()
      })
    steps.append(
      Step(weight: 2, name: "peer-create-habit") { [self] in
        counter += 1
        _ = try? await core.createHabit(
          name: "Peer habit \(counter)", cue: nil, icon: nil, color: nil, targetCount: 2,
          cadence: .daily, milestoneTarget: nil)
        await inbound([.habit])
      })
    if let h = pick(coreActive) {
      steps.append(
        Step(weight: 4, name: "assistant-complete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.completeHabit(id: h.id, date: store.logicalTodayDateString)
          await store.refresh()
        })
      steps.append(
        Step(weight: 4, name: "peer-complete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.completeHabit(id: h.id, date: store.logicalTodayDateString)
          await inbound([.habitCompletion])
        })
      steps.append(
        Step(weight: 3, name: "assistant-archive-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: true)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-archive-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: true)
          await inbound([.habit])
        })
      steps.append(
        Step(weight: 2, name: "assistant-rename-habit \(habitBrief(h))") { [self] in
          counter += 1
          _ = try? await core.updateHabit(
            id: h.id, name: "Assistant rename \(counter)", cue: .unset, color: nil, icon: nil,
            targetCount: nil, archived: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 2, name: "peer-rename-habit \(habitBrief(h))") { [self] in
          counter += 1
          _ = try? await core.updateHabit(
            id: h.id, name: "Peer rename \(counter)", cue: .unset, color: nil, icon: nil,
            targetCount: nil, archived: nil)
          await inbound([.habit])
        })
      steps.append(
        Step(weight: 2, name: "assistant-delete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await store.refresh()
        })
      steps.append(
        Step(weight: 2, name: "peer-delete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await inbound([.habit])
        })
      steps.append(
        Step(weight: 3, name: "peer-habit-reminder \(habitBrief(h))") { [self] in
          let policy = HabitReminderPolicy(
            id: "", habitID: h.id, habitName: "", reminderTime: "08:15", enabled: true,
            createdAt: "", updatedAt: "")
          _ = try? await core.upsertHabitReminderPolicy(id: h.id, policy: policy)
          await inbound([.habitReminderPolicy])
        })
    }
    if let id = store.selectedHabitID, coreActive.contains(where: { $0.id == id }) {
      steps.append(
        Step(weight: 6, name: "assistant-complete-open-habit \(id.prefix(6))") { [self] in
          _ = try? await core.completeHabit(id: id, date: store.logicalTodayDateString)
          await store.refresh()
        })
      steps.append(
        Step(weight: 6, name: "peer-complete-open-habit \(id.prefix(6))") { [self] in
          _ = try? await core.completeHabit(id: id, date: store.logicalTodayDateString)
          await inbound([.habitCompletion])
        })
    }
    if let h = pick(coreArchived) {
      steps.append(
        Step(weight: 3, name: "assistant-restore-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: false)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "assistant-rename-archived-habit \(habitBrief(h))") { [self] in
          counter += 1
          _ = try? await core.updateHabit(
            id: h.id, name: "Archived rename \(counter)", cue: .unset, color: nil, icon: nil,
            targetCount: nil, archived: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-delete-archived-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await inbound([.habit])
        })
    }

    // MARK: lists

    steps.append(
      Step(weight: 3, name: "create-list") { [self] in
        counter += 1
        store.beginCreateListDraft()
        store.draftListName = "List \(counter)"
        await store.createDraftList()
      })
    if let l = pick(lists) {
      steps.append(
        Step(weight: 3, name: "update-list \(listBrief(l))") { [self] in
          counter += 1
          store.prepareListDraft(for: l)
          store.draftListName = "Renamed list \(counter)"
          await store.updateList(l)
        })
      steps.append(
        Step(weight: 4, name: "select-list \(listBrief(l))") { [self] in
          store.selection = .lists
          store.selectedListID = l.id
          await store.loadSelectedListDetailForUI()
        })
      if !l.isInbox {
        steps.append(
          Step(weight: 2, name: "archive-list \(listBrief(l))") { [self] in
            await store.archiveList(l)
          })
        if l.totalCount == 0 {
          steps.append(
            Step(weight: 3, name: "delete-list \(listBrief(l))") { [self] in
              await store.deleteList(l)
            })
        }
      }
    }
    if let l = pick(store.archivedLists?.lists ?? []) {
      steps.append(
        Step(weight: 3, name: "unarchive-list \(listBrief(l))") { [self] in
          await store.unarchiveList(l)
        })
    }
    steps.append(
      Step(weight: 5, name: "create-task") { [self] in
        counter += 1
        await store.captureLine("Entity task \(counter)")
      })
    if let task = pick(store.today.tasks) {
      steps.append(
        Step(weight: 4, name: "complete-task \(task.id.prefix(6))") { [self] in
          await store.completeTask(id: task.id)
        })
    }
    steps.append(
      Step(weight: 2, name: "assistant-create-list") { [self] in
        counter += 1
        _ = try? await core.createList(name: "Assistant list \(counter)", description: nil)
        await store.refresh()
      })
    steps.append(
      Step(weight: 2, name: "peer-create-list") { [self] in
        counter += 1
        _ = try? await core.createList(name: "Peer list \(counter)", description: nil)
        await inbound([.list])
      })
    if let l = pick(coreLists) {
      steps.append(
        Step(weight: 2, name: "assistant-rename-list \(listBrief(l))") { [self] in
          counter += 1
          _ = try? await core.updateList(
            id: l.id, name: "Assistant list rename \(counter)", description: .unset, color: nil,
            icon: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 2, name: "peer-rename-list \(listBrief(l))") { [self] in
          counter += 1
          _ = try? await core.updateList(
            id: l.id, name: "Peer list rename \(counter)", description: .unset, color: nil,
            icon: nil)
          await inbound([.list])
        })
      if !l.isInbox {
        steps.append(
          Step(weight: 2, name: "peer-archive-list \(listBrief(l))") { [self] in
            _ = try? await core.archiveList(id: l.id)
            await inbound([.list])
          })
        if l.totalCount == 0 {
          steps.append(
            Step(weight: 2, name: "assistant-delete-list \(listBrief(l))") { [self] in
              try? await core.deleteList(id: l.id)
              await store.refresh()
            })
          steps.append(
            Step(weight: 2, name: "peer-delete-list \(listBrief(l))") { [self] in
              try? await core.deleteList(id: l.id)
              await inbound([.list])
            })
        }
      }
    }

    // MARK: memory

    steps.append(
      Step(weight: 4, name: "new-memory") { [self] in
        counter += 1
        store.clearMemoryDraft()
        store.memoryKeyDraft = "key \(counter)"
        store.memoryContentDraft = "content \(counter)"
        await store.saveMemoryDraft()
      })
    if let e = pick(entries) {
      steps.append(
        Step(weight: 3, name: "edit-memory \(memoryBrief(e))") { [self] in
          counter += 1
          store.beginEditingMemory(e)
          if chance(2) { store.memoryKeyDraft = "key \(counter)" }
          store.memoryContentDraft = "edited \(counter)"
          await store.saveMemoryDraft()
        })
      steps.append(
        Step(weight: 2, name: "delete-memory \(memoryBrief(e))") { [self] in
          await store.deleteMemoryEntry(e)
        })
      steps.append(
        Step(weight: 1, name: "begin-editing-then-delete \(memoryBrief(e))") { [self] in
          store.beginEditingMemory(e)
          await store.deleteMemoryEntry(e)
        })
    }
    steps.append(
      Step(weight: 3, name: "assistant-memory-upsert") { [self] in
        counter += 1
        let key = pick(coreEntries)?.key ?? "assistant \(counter)"
        _ = try? await core.upsertMemory(
          key: chance(2) ? key : "assistant \(counter)", content: "assistant \(counter)")
        await store.refresh()
      })
    steps.append(
      Step(weight: 3, name: "peer-memory-upsert") { [self] in
        counter += 1
        let key = pick(coreEntries)?.key ?? "peer \(counter)"
        _ = try? await core.upsertMemory(
          key: chance(2) ? key : "peer \(counter)", content: "peer \(counter)")
        await inbound([.memory])
      })
    if let e = pick(coreEntries) {
      steps.append(
        Step(weight: 1, name: "assistant-memory-delete \(memoryBrief(e))") { [self] in
          _ = try? await core.deleteMemory(key: e.key)
          await store.refresh()
        })
      steps.append(
        Step(weight: 2, name: "peer-memory-delete \(memoryBrief(e))") { [self] in
          _ = try? await core.deleteMemory(key: e.key)
          await inbound([.memory])
        })
    }
    // MARK: calendar

    if store.selection == .calendar {
      steps.append(
        Step(weight: 4, name: "calendar-step") { [self] in
          let direction = chance(2) ? 1 : -1
          calendarAnchor = calendarMode.anchor(
            calendarAnchor, steppedBy: direction, calendar: Calendar.current)
          trace[trace.count - 1] += " \(direction) \(calendarMode)"
        })
      steps.append(
        Step(weight: 3, name: "calendar-mode") { [self] in
          calendarMode = pick(CalendarPresentationMode.allCases) ?? .week
          trace[trace.count - 1] += " \(calendarMode)"
        })
    }
    let timelineEvents = (store.calendarTimeline?.events ?? []).filter {
      $0.editable && !$0.supportsScopedMutation
    }
    var coreWindowEvents: [CalendarTimelineEvent] = []
    if let timeline = store.calendarTimeline,
      let fresh = try? await core.loadCalendarTimeline(from: timeline.from, to: timeline.to)
    {
      coreWindowEvents = fresh.events.filter { $0.editable && !$0.supportsScopedMutation }
    }
    steps.append(
      Step(weight: 5, name: "create-event") { [self] in
        counter += 1
        let start = Date().addingTimeInterval(
          Double(Int(rng.next() % 4)) * 86_400 + Double(1 + Int(rng.next() % 8)) * 3_600)
        store.beginCreateCalendarDraft()
        store.draftCalendarTitle = "Event \(counter)"
        store.draftCalendarTiming =
          chance(4)
          ? CalendarEventTiming(start: start, end: start, allDay: true)
          : CalendarEventTiming.timed(startingAt: start)
        if chance(3) { store.draftCalendarLocation = "Room \(counter)" }
        trace[trace.count - 1] += " allDay=\(store.draftCalendarTiming.allDay)"
        await store.createDraftCalendarEvent()
      })
    steps.append(
      Step(weight: 3, name: "assistant-create-event") { [self] in
        counter += 1
        let day =
          LorvexDateFormatters.ymdUTCAddingDays(
            store.logicalTodayDateString, days: Int(rng.next() % 4)) ?? store.logicalTodayDateString
        _ = try? await core.createCalendarEvent(
          title: "Assistant event \(counter)", startDate: day, endDate: nil, startTime: "10:00",
          endTime: "11:00", allDay: false, location: nil, notes: nil)
        await store.refresh()
      })
    steps.append(
      Step(weight: 3, name: "peer-create-event") { [self] in
        counter += 1
        let day =
          LorvexDateFormatters.ymdUTCAddingDays(
            store.logicalTodayDateString, days: Int(rng.next() % 4)) ?? store.logicalTodayDateString
        _ = try? await core.createCalendarEvent(
          title: "Peer event \(counter)", startDate: day, endDate: nil, startTime: "14:00",
          endTime: "15:30", allDay: false, location: "Peer room", notes: nil)
        await inbound([.calendarEvent])
      })
    if let ev = pick(timelineEvents) {
      steps.append(
        Step(weight: 4, name: "update-event \(eventBrief(ev))") { [self] in
          counter += 1
          store.prepareCalendarDraft(for: ev)
          store.draftCalendarTitle = "Edited event \(counter)"
          if chance(2) {
            let shifted = store.draftCalendarTiming.start.addingTimeInterval(
              Double(1 + Int(rng.next() % 3)) * 86_400)
            store.draftCalendarTiming = .timed(startingAt: shifted)
          }
          await store.updateCalendarEvent(ev)
        })
      steps.append(
        Step(weight: 3, name: "reschedule-event \(eventBrief(ev))") { [self] in
          let start = CalendarEventTiming(event: ev, fallbackDay: Date()).start
            .addingTimeInterval(Double(1 + Int(rng.next() % 5)) * 3_600)
          await store.rescheduleCalendarEvent(
            ev, newStart: start, newEnd: start.addingTimeInterval(3_600))
        })
      steps.append(
        Step(weight: 3, name: "delete-event \(eventBrief(ev))") { [self] in
          await store.deleteCalendarEvent(ev)
        })
      steps.append(
        Step(weight: 4, name: "select-event \(eventBrief(ev))") { [self] in
          store.toggleCalendarEventSelection(ev)
        })
    }
    if store.selectedCalendarEventID != nil {
      steps.append(
        Step(weight: 2, name: "deselect-event") { [self] in store.clearSelectedCalendarEvent() })
    }
    if let ev = pick(coreWindowEvents) {
      steps.append(
        Step(weight: 3, name: "assistant-edit-event \(eventBrief(ev))") { [self] in
          counter += 1
          _ = try? await core.updateCalendarEvent(
            id: ev.eventID, title: "Assistant edit \(counter)", startDate: nil, endDate: nil,
            startTime: nil, endTime: nil, allDay: nil, location: "Assistant room", notes: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 2, name: "assistant-delete-event \(eventBrief(ev))") { [self] in
          _ = try? await core.deleteCalendarEvent(id: ev.eventID)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-edit-event \(eventBrief(ev))") { [self] in
          counter += 1
          _ = try? await core.updateCalendarEvent(
            id: ev.eventID, title: "Peer edit \(counter)", startDate: nil, endDate: nil,
            startTime: nil, endTime: nil, allDay: nil, location: nil, notes: "peer note")
          await inbound([.calendarEvent])
        })
      steps.append(
        Step(weight: 2, name: "peer-delete-event \(eventBrief(ev))") { [self] in
          _ = try? await core.deleteCalendarEvent(id: ev.eventID)
          await inbound([.calendarEvent])
        })
    }

    // Tasks the calendar draws: planned onto days (and times) through the store,
    // the assistant and a peer.
    var planPool = store.today.tasks.filter { $0.status.isActionable }
    for task in (store.calendarScheduledTasks ?? []) where task.status.isActionable {
      if !planPool.contains(where: { $0.id == task.id }) { planPool.append(task) }
    }
    if let task = pick(planPool) {
      let days = Int(rng.next() % 6)
      let hour = 7 + Int(rng.next() % 10)
      steps.append(
        Step(weight: 5, name: "plan-task \(task.id.prefix(6)) +\(days)d") { [self] in
          await store.planTasks(ids: [task.id], daysFromToday: days)
        })
      steps.append(
        Step(weight: 3, name: "assistant-plan-task \(task.id.prefix(6)) +\(days)d") { [self] in
          guard let date = try? store.storageDate(daysFromLogicalToday: days) else { return }
          _ = try? await core.updateTask(
            TaskUpdateDraft(
              id: task.id, plannedDate: .set(date),
              plannedTime: chance(2) ? .set((hour * 60)..<(hour * 60 + 45)) : .clear))
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-plan-task \(task.id.prefix(6)) +\(days)d") { [self] in
          guard let date = try? store.storageDate(daysFromLogicalToday: days) else { return }
          _ = try? await core.updateTask(
            TaskUpdateDraft(
              id: task.id, plannedDate: .set(date),
              plannedTime: chance(2) ? .set((hour * 60)..<(hour * 60 + 45)) : .clear))
          await inbound([.task])
        })
      steps.append(
        Step(weight: 2, name: "complete-planned-task \(task.id.prefix(6))") { [self] in
          await store.completeTask(id: task.id)
        })
    }

    // MARK: reviews

    let reviewsOpen = store.selection == .reviews
    steps.append(
      Step(weight: reviewsOpen ? 1 : 5, name: "open-reviews") { [self] in
        store.selection = .reviews
      })
    steps.append(
      Step(weight: 2, name: "assistant-review") { [self] in
        counter += 1
        let date = chance(2) ? store.selectedReviewDate : store.logicalTodayDateString
        trace[trace.count - 1] += " \(date)"
        _ = try? await core.upsertDailyReview(
          date: date, summary: "Assistant \(counter)", mood: 3, energyLevel: 4, wins: "aw",
          blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
        await store.refresh()
      })
    steps.append(
      Step(weight: 2, name: "peer-review") { [self] in
        counter += 1
        let date = chance(2) ? store.selectedReviewDate : store.logicalTodayDateString
        trace[trace.count - 1] += " \(date)"
        _ = try? await core.upsertDailyReview(
          date: date, summary: "Peer \(counter)", mood: 2, energyLevel: 5, wins: "pw",
          blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
        await inbound([.dailyReview])
      })
    if reviewsOpen {
      // Everything below is something the Reviews page offers while it is on screen.
      let editable = store.selectedReviewDayIsEditable
      steps.append(
        Step(weight: 9, name: "review-scope-\(reviewMode == .daily ? "weekly" : "daily")") {
          [self] in
          reviewMode = reviewMode == .daily ? .weekly : .daily
          if reviewMode != .daily {
            let dirty = !store.dailyReviewDraftMatchesLoaded
            await store.flushDailyReviewDraftIfNeeded()
            await loopbackAfterFlush(wasDirty: dirty)
          }
        })
      if reviewMode == .daily {
        let day = Int(rng.next() % 11)
        steps.append(
          Step(weight: 12, name: "open-review-day \(day)d ago") { [self] in
            let dirty = !store.dailyReviewDraftMatchesLoaded
            await store.selectReviewDay(daysAgo(day))
            await loopbackAfterFlush(wasDirty: dirty)
            expectedDraft = loadedDraftValues()
          })
        steps.append(
          Step(weight: 9, name: "step-review-day") { [self] in
            let delta = chance(2) ? -1 : 1
            guard delta < 0 || !store.isViewingCurrentDay else { return }
            let dirty = !store.dailyReviewDraftMatchesLoaded
            await store.stepReviewDay(by: delta)
            await loopbackAfterFlush(wasDirty: dirty)
            expectedDraft = loadedDraftValues()
          })
        if !store.isViewingCurrentDay {
          steps.append(
            Step(weight: 6, name: "review-jump-today") { [self] in
              let dirty = !store.dailyReviewDraftMatchesLoaded
              await store.selectReviewDay(store.logicalTodayDateString)
              await loopbackAfterFlush(wasDirty: dirty)
              expectedDraft = loadedDraftValues()
            })
        }
        if store.dailyReviewEditingDate != nil {
          steps.append(
            Step(weight: 6, name: "review-back-to-today") { [self] in
              let dirty = !store.dailyReviewDraftMatchesLoaded
              await store.endEditingDailyReview()
              await loopbackAfterFlush(wasDirty: dirty)
              expectedDraft = loadedDraftValues()
            })
        }
        if editable {
          steps.append(
            Step(weight: 21, name: "type-review") { [self] in
              counter += 1
              switch rng.next() % 8 {
              case 0: store.dailyReviewSummaryDraft = chance(3) ? "" : "Summary \(counter)"
              case 1: store.dailyReviewSummaryDraft += chance(2) ? " " : "\n"
              case 2: store.dailyReviewWinsDraft = "Win \(counter)" + (chance(2) ? "  " : "")
              case 3: store.dailyReviewBlockersDraft = chance(3) ? "" : "Block \(counter)\n"
              case 4: store.dailyReviewLearningsDraft = " Learned \(counter) "
              case 5: store.dailyReviewMood = chance(4) ? nil : 1 + Int(rng.next() % 5)
              case 6: store.dailyReviewEnergy = chance(4) ? nil : 1 + Int(rng.next() % 5)
              default: store.dailyReviewWinsDraft += chance(2) ? " " : "\n"
              }
            })
          if !store.dailyReviewDraftMatchesLoaded {
            // The editor's debounce fires once the draft stopped changing.
            steps.append(
              Step(weight: 90, name: "autosave-review") { [self] in
                let typed = store.dailyReviewDraftValues
                await store.saveDailyReviewDraft()
                expectedDraft = typed
                if !store.dailyReviewDraftMatchesLoaded {
                  fail("autosave-left-dirty", "draft \(typed) loaded \(reviewBrief(store.dailyReview))")
                }
              })
          }
        }
        if let task = pick(store.dayReviewEvidence?.dueOpenTasks ?? []) {
          steps.append(
            Step(weight: 9, name: "review-complete-task \(task.id.prefix(6))") { [self] in
              await store.completeTask(id: task.id)
            })
        }
        if let ids = store.dayReviewEvidence?.dueOpenTasks.map(\.id), !ids.isEmpty {
          steps.append(
            Step(weight: 6, name: "review-move-to-tomorrow \(ids.count)") { [self] in
              await store.moveReviewTasksToTomorrow(ids: ids)
            })
        }
      } else {
        let day = daysAgo(Int(rng.next() % 30))
        steps.append(
          Step(weight: 12, name: "review-week-of \(day)") { [self] in
            await store.selectReviewWeek(of: day)
          })
        steps.append(
          Step(weight: 9, name: "step-review-week") { [self] in
            await store.stepWeeklyReview(byWeeks: chance(2) ? -1 : 1)
          })
        if !store.isViewingCurrentWeek {
          steps.append(
            Step(weight: 6, name: "review-jump-this-week") { [self] in
              await store.jumpWeeklyReviewToCurrentWeek()
            })
        }
        if let entry = pick(store.weekReviewDigest) {
          steps.append(
            Step(weight: 9, name: "review-digest-open-day \(entry.date)") { [self] in
              let dirty = !store.dailyReviewDraftMatchesLoaded
              await store.selectReviewDay(entry.date)
              reviewMode = .daily
              await loopbackAfterFlush(wasDirty: dirty)
              expectedDraft = loadedDraftValues()
            })
        }
        if let task = pick(store.weeklyReview?.overdueTasks ?? []) {
          steps.append(
            Step(weight: 6, name: "review-park-task \(task.id.prefix(6))") { [self] in
              await store.parkReviewTaskInSomeday(task.id)
            })
        }
      }
    }

    steps.append(
      Step(weight: 3, name: "refresh") { [self] in
        await store.refresh()
      })
    return steps
  }

  // MARK: View triggers

  /// The Calendar workspace's fetch of the period it shows: day and week load the
  /// store's default window from the period's first day, month loads the whole
  /// weeks its grid draws.
  func fetchVisiblePeriod() async {
    let calendar = Calendar.current
    let period = CalendarVisiblePeriod(mode: calendarMode, anchor: calendarAnchor, calendar: calendar)
    let monthGrid = CalendarMonthGridModel.gridRange(
      forMonthContaining: period.start, calendar: calendar)
    switch period.mode {
    case .day, .week:
      try? await store.refreshCalendarTimeline(anchorDate: period.start)
    case .month:
      try? await store.refreshCalendarTimeline(
        anchorDate: monthGrid.start, dayCount: monthGrid.dayCount)
    }
    lastFetchedPeriod = period
  }

  /// What the workspaces and the inspector do on their own once the store state
  /// changed.
  func settleViews() async {
    let habitsOpen = store.selection == .habits
    if habitsOpen, !openedHabits {
      await store.loadAllHabitStats()
      await store.loadArchivedHabits()
    }
    openedHabits = habitsOpen
    let listsOpen = store.selection == .lists
    if listsOpen, !openedLists { await store.loadSelectedListDetailForUI() }
    openedLists = listsOpen
    let memoryOpen = store.selection == .memory
    if memoryOpen, !openedMemory { await store.loadMemory() }
    openedMemory = memoryOpen
    // The Calendar workspace fetches its visible period when it appears, when the
    // period changes, and when the Today snapshot changes.
    let calendarOpen = store.selection == .calendar
    if calendarOpen {
      let period = CalendarVisiblePeriod(
        mode: calendarMode, anchor: calendarAnchor, calendar: Calendar.current)
      if !openedCalendar || period != lastFetchedPeriod || store.today != lastSeenToday {
        await fetchVisiblePeriod()
      }
    }
    openedCalendar = calendarOpen
    lastSeenToday = store.today
    let todayOpen = store.selection == .today
    if todayOpen, !openedToday { await store.loadTodaySchedule() }
    openedToday = todayOpen
    // The Reviews workspace: a fresh appearance starts on the day page, the Week
    // scope loads its digest when it appears, and leaving the page flushes the
    // pending draft.
    let reviewsOpen = store.selection == .reviews
    if reviewsOpen, !openedReviews { reviewMode = .daily }
    if openedReviews, !reviewsOpen {
      let dirty = !store.dailyReviewDraftMatchesLoaded
      await store.flushDailyReviewDraftIfNeeded()
      await loopbackAfterFlush(wasDirty: dirty)
    }
    if reviewsOpen, reviewMode == .weekly, !openedReviewWeek {
      await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
    }
    openedReviewWeek = reviewsOpen && reviewMode == .weekly
    openedReviews = reviewsOpen
    // The inspector is up while a habit is selected in the Habits workspace and
    // loads its detail when the habit changes.
    if habitsOpen, let id = store.selectedHabitID {
      if inspectorHabitID != id {
        inspectorHabitID = id
        await store.loadHabitDetail(id: id)
      }
    } else if store.selectedHabitID == nil {
      inspectorHabitID = nil
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

    // Habit catalog.
    let wantHabits = await coreHabits().map(habitBrief)
    let haveHabits = store.orderedHabits.sorted { $0.position < $1.position }.map(habitBrief)
    if Set(wantHabits) != Set(haveHabits) {
      let missing = Set(wantHabits).subtracting(haveHabits).sorted()
      let extra = Set(haveHabits).subtracting(wantHabits).sorted()
      fail("habits-stale", "missing \(missing) extra \(extra)")
    }

    let habitsOpen = store.selection == .habits
    if habitsOpen {
      coverage["data.habitsOpenChecks", default: 0] += 1
      let wantArchived = await coreArchivedHabits().map(archivedBrief)
      let haveArchived = store.archivedHabits.map(archivedBrief)
      if !haveArchived.isEmpty { coverage["data.archivedNonEmpty", default: 0] += 1 }
      if wantArchived != haveArchived {
        let missing = Set(wantArchived).subtracting(haveArchived).sorted()
        let extra = Set(haveArchived).subtracting(wantArchived).sorted()
        fail("archived-stale", "missing \(missing) extra \(extra)")
      }
      // The cards' stats.
      for habit in await coreHabits() {
        guard let fresh = try? await core.getHabitStats(id: habit.id) else { continue }
        if store.habitStats(for: habit.id) != fresh {
          fail("habit-stats-stale", "\(habit.id.prefix(6)) store \(String(describing: store.habitStats(for: habit.id)?.totalCompletions)) core \(fresh.totalCompletions)")
        }
      }
      if let selected = store.selectedHabitID,
        !store.orderedHabits.contains(where: { $0.id == selected })
      {
        fail("selected-habit-dangling", "\(selected.prefix(6))")
      }
      if let id = store.selectedHabitID, store.orderedHabits.contains(where: { $0.id == id }) {
        coverage["data.inspectorChecks", default: 0] += 1
        await checkHabitDetail(id)
      }
    }

    // Lists.
    if let shown = store.lists?.lists, let fresh = try? await core.loadLists() {
      let want = fresh.lists.map(listBrief)
      let have = shown.map(listBrief)
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("lists-stale", "missing \(missing) extra \(extra)")
      }
    }
    if let shown = store.archivedLists?.lists, let fresh = try? await core.loadArchivedLists() {
      let want = fresh.lists.map(archivedListBrief).sorted()
      let have = shown.map(archivedListBrief).sorted()
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("archived-lists-stale", "missing \(missing) extra \(extra)")
      }
    }
    if store.selection == .lists, let id = store.selectedListID {
      coverage["data.listDetailChecks", default: 0] += 1
      if let detail = store.selectedListDetail {
        if detail.list.id != id { fail("list-detail-wrong-list", "\(detail.list.id.prefix(6)) vs \(id.prefix(6))") }
        if let fresh = try? await core.loadListDetail(id: id, limit: 500, offset: 0) {
          let want = fresh.tasks.map(\.id).sorted()
          let have = detail.tasks.map(\.id).sorted()
          if want != have {
            fail("list-detail-stale", "store \(have.count) tasks core \(want.count) tasks")
          }
          if listBrief(detail.list) != listBrief(fresh.list) {
            fail("list-detail-header-stale", "store \(listBrief(detail.list)) core \(listBrief(fresh.list))")
          }
        }
      } else {
        fail("list-detail-missing", "\(id.prefix(6))")
      }
    }

    // Memory.
    if let shown = store.memory?.entries, let fresh = try? await core.loadMemory() {
      coverage["data.memoryChecks", default: 0] += 1
      let want = fresh.entries.map(memoryBrief)
      let have = shown.map(memoryBrief)
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("memory-stale", "missing \(missing) extra \(extra)")
      }
      if let editing = store.memoryEditingKey, !fresh.entries.contains(where: { $0.key == editing }) {
        fail("memory-editing-key-dangling", editing)
      }
    }

    // Calendar: the loaded window equals a fresh read of itself.
    if let timeline = store.calendarTimeline,
      let fresh = try? await core.loadCalendarTimeline(from: timeline.from, to: timeline.to)
    {
      coverage["data.calendarChecks", default: 0] += 1
      if !fresh.events.isEmpty { coverage["data.calendarNonEmpty", default: 0] += 1 }
      // An event created past the window's edge stays in the list until the next
      // window load; the grids draw only days inside the window.
      let inWindow: (CalendarTimelineEvent) -> Bool = {
        $0.startDate <= timeline.to && ($0.endDate ?? $0.startDate) >= timeline.from
      }
      let want = fresh.events.filter(inWindow).map(eventBrief).sorted()
      let have = timeline.events.filter(inWindow).map(eventBrief).sorted()
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("calendar-events-stale", "missing \(missing) extra \(extra)")
      }
      if let id = store.selectedCalendarEventID, !fresh.events.contains(where: { $0.id == id }) {
        coverage["data.selectedEventDangling", default: 0] += 1
        if store.selectedCalendarEvent != nil {
          fail("selected-event-resolves-deleted", "\(id.prefix(8))")
        }
      }
      // The tasks the grids draw are read only while the Calendar is on screen
      // (every other surface refetches them when it appears).
      if store.selection == .calendar, openedCalendar,
        let shown = store.calendarScheduledTasks,
        let freshTasks = try? await core.getScheduledTasks(
          from: timeline.from, to: timeline.to, limit: CalendarGridModel.windowTaskLimit)
      {
        coverage["data.scheduledChecks", default: 0] += 1
        if !freshTasks.isEmpty { coverage["data.scheduledNonEmpty", default: 0] += 1 }
        let wantTasks = freshTasks.map(scheduledBrief).sorted()
        let haveTasks = shown.map(scheduledBrief).sorted()
        if wantTasks != haveTasks {
          let missing = Set(wantTasks).subtracting(haveTasks).sorted()
          let extra = Set(haveTasks).subtracting(wantTasks).sorted()
          fail("calendar-scheduled-tasks-stale", "missing \(missing) extra \(extra)")
        }
      }
    }

    // Today's schedule rows come from the same window.
    if store.selection == .today, openedToday {
      let day = store.logicalTodayDateString
      if let fresh = try? await core.loadCalendarTimeline(from: day, to: day) {
        coverage["data.todayScheduleChecks", default: 0] += 1
        let want = fresh.eventsOccurring(on: day).map(eventBrief)
        let have = store.todayScheduleEvents.map(eventBrief)
        if !want.isEmpty { coverage["data.todayScheduleNonEmpty", default: 0] += 1 }
        if want != have {
          let missing = Set(want).subtracting(have).sorted()
          let extra = Set(have).subtracting(want).sorted()
          fail("today-schedule-stale", "missing \(missing) extra \(extra)")
        }
      }
    }

    await checkReviews()
  }

  /// The daily review the editor holds, and what the Reviews page shows on screen
  /// (the day's evidence, the viewed week's snapshot and its digest).
  func checkReviews() async {
    let day = store.dailyReviewEditorDate
    if let fresh = try? await core.loadDailyReview(date: day) {
      coverage["data.reviewSaved", default: 0] += 1
      if store.dailyReview != fresh {
        fail(
          "review-stale",
          "store \(reviewBrief(store.dailyReview)) core \(reviewBrief(fresh)) day \(day)")
      }
      if !store.dailyReviewDraftMatchesLoaded { coverage["data.reviewDirty", default: 0] += 1 }
    }
    if let loaded = store.dailyReview, loaded.date != day {
      fail("review-wrong-day", "loaded \(loaded.date) editor \(day)")
    }
    if store.dailyReviewEditingDate != nil, store.dailyReviewEditingDate != day {
      fail("review-editing-date", "editing \(store.dailyReviewEditingDate ?? "-") editor \(day)")
    }

    if let expected = expectedDraft {
      expectedDraft = nil
      if store.dailyReviewDraftValues != expected {
        fail("review-editor-changed", "editor \(store.dailyReviewDraftValues) expected \(expected)")
      }
    }

    guard openedReviews else { return }
    coverage["data.reviewsOpenChecks", default: 0] += 1
    if reviewMode == .daily {
      if let fresh = try? await core.loadDaySummary(date: store.selectedReviewDate) {
        coverage["data.reviewEvidenceChecks", default: 0] += 1
        if store.dayReviewEvidence != fresh {
          fail(
            "review-evidence-stale",
            "store \(evidenceBrief(store.dayReviewEvidence)) core \(evidenceBrief(fresh))")
        }
      }
    }
    if let fresh = try? await core.getWeeklyReviewSnapshot(weekOf: store.weeklyReviewAnchor) {
      coverage["data.reviewWeekChecks", default: 0] += 1
      if store.weeklyReview != fresh {
        fail("review-week-stale", "store \(weekBrief(store.weeklyReview)) core \(weekBrief(fresh))")
      }
    }
    if reviewMode == .weekly {
      let to = store.weeklyReviewAnchor ?? store.logicalTodayDateString
      let from = LorvexDateFormatters.ymdUTCAddingDays(to, days: -6) ?? to
      if let fresh = try? await core.getReviewHistory(from: from, to: to, limit: 7) {
        coverage["data.reviewDigestChecks", default: 0] += 1
        if store.weekReviewDigest != fresh {
          fail(
            "review-digest-stale",
            "store \(store.weekReviewDigest.map(\.date)) core \(fresh.map(\.date)) window \(from)...\(to)"
          )
        }
      }
    }
  }

  func checkHabitDetail(_ id: String) async {
    guard let shown = store.habitDetail(for: id) else {
      return fail("habit-detail-missing", "\(id.prefix(6))")
    }
    let to = store.logicalTodayDateString
    let from = LorvexDateFormatters.ymdUTCAddingDays(to, days: -370) ?? to
    guard let stats = try? await core.getHabitStats(id: id),
      let completions = try? await core.getHabitCompletions(id: id, from: from, to: to, limit: 400),
      let policies = try? await core.getHabitReminderPolicies(id: id)
    else { return }
    if shown.stats != stats {
      fail("habit-detail-stats-stale", "store total \(shown.stats.totalCompletions) core \(stats.totalCompletions)")
    }
    if shown.completions != completions {
      fail(
        "habit-detail-completions-stale",
        "store \(shown.completions.completions.count) rows core \(completions.completions.count) rows"
      )
    }
    if shown.reminderPolicies != policies {
      fail(
        "habit-detail-policies-stale",
        "store \(shown.reminderPolicies.count) core \(policies.count)")
    }
  }

  // MARK: Walk

  func run(steps count: Int) async {
    for _ in 0..<count {
      guard let step = weightedPick(await buildSteps()) else { return }
      trace.append(step.name)
      coverage["step." + (step.name.split(separator: " ").first.map(String.init) ?? step.name), default: 0] += 1
      store.errorMessage = nil
      await step.run()
      if loopback, writesThroughStore(step.name) { await store.refresh() }
      stepFailures = 0
      await settleViews()
      await check()
      if stepFailures > 0 {
        // Heal to the store's own ground truth so the next step starts clean.
        await store.refresh()
        await store.loadAllHabitStats()
        await store.loadArchivedHabits()
        await store.loadMemory()
        if let id = store.selectedHabitID { await store.loadHabitDetail(id: id) }
        await store.loadSelectedListDetailForUI()
        store.syncDailyReviewDraft()
        expectedDraft = nil
      }
    }
  }
}

@MainActor
@Test
func zzAppEntityWalkProbe() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let seed = env["AENTITY_SEED"].flatMap(UInt64.init) else { return }
  let steps = env["AENTITY_STEPS"].flatMap(Int.init) ?? 60
  let walk = try await AppEntityWalk(seed: seed, sabotage: env["AENTITY_SABOTAGE"] ?? "")
  await walk.run(steps: steps)
  print(
    "AWALK seed=\(seed) steps=\(walk.trace.count) failures=\(walk.failures.count) notes=\(walk.notes.count)"
  )
  for note in walk.notes.prefix(12) { print("AWALK note \(note)") }
  if env["AENTITY_COVERAGE"] != nil {
    for (key, count) in walk.coverage.sorted(by: { $0.key < $1.key }) {
      print("AWALK coverage \(key)=\(count)")
    }
  }
  if !walk.failures.isEmpty {
    if env["AENTITY_TRACE"] != nil {
      for (index, line) in walk.trace.enumerated() { print("AWALK trace \(index + 1): \(line)") }
    }
    for failure in walk.failures { print("AWALK FAIL seed=\(seed) \(failure)") }
  }
}
