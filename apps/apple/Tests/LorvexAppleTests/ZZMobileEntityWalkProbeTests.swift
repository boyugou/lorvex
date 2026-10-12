import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexMobile

// Scratch probe (git-excluded): a seeded random walk over MobileStore's habit,
// list, memory and daily-review operations, plus assistant-style edits made
// straight through the core and followed by a full refresh (which is what the
// in-process change signal triggers). After every step each surface the store
// keeps must agree with the core, modelling what the iOS views do on their own
// triggers:
//   * the Habits view reloads the archived list and prunes its selection when
//     the active habit-id set changes (and on appear);
//   * an open habit detail re-reads its data when `habitDetailRevision` moves;
//   * the Memory view prunes its selection when the key set changes.
// ENTITY_SEED = RNG seed, ENTITY_STEPS = operations per walk (default 60).
// Does nothing without ENTITY_SEED. Prints one `EWALK seed=… steps=… failures=…`
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

/// What a row of the archived section shows: its icon tile and its name.
private func archivedBrief(_ h: LorvexHabit) -> String {
  "\(h.id.prefix(6)) '\(h.name)' icon=\(h.icon ?? "-")"
}

private func listBrief(_ l: LorvexList) -> String {
  "\(l.id.prefix(6)) '\(l.name)' desc=\(l.description ?? "-") color=\(l.color ?? "-") "
    + "icon=\(l.icon ?? "-") \(l.openCount)/\(l.completedCount)/\(l.cancelledCount)/\(l.totalCount) "
    + "arch=\(l.archivedAt ?? "-") pos=\(l.position)"
}

private func eventBrief(_ e: CalendarTimelineEvent) -> String {
  "\(e.id.prefix(8)) '\(e.title)' \(e.startDate) \(e.startTime ?? "-") -> "
    + "\(e.endDate ?? "-") \(e.endTime ?? "-") allDay=\(e.allDay) loc=\(e.location ?? "-") "
    + "notes=\(e.notes ?? "-")"
}

private func memoryBrief(_ e: MemoryEntry) -> String { "'\(e.key)'=\(e.content.prefix(24))" }

private func reviewBrief(_ r: DailyReviewEntry?) -> String {
  guard let r else { return "nil" }
  return "\(r.date) s='\(r.summary)' mood=\(r.mood.map(String.init) ?? "-") "
    + "energy=\(r.energyLevel.map(String.init) ?? "-") w=\(r.wins ?? "-") b=\(r.blockers ?? "-") "
    + "l=\(r.learnings ?? "-")"
}

@MainActor
private final class EntityWalk {
  let core: SwiftLorvexCoreService
  let store: MobileStore
  var rng: SplitMix64
  var trace: [String] = []
  var failures: [String] = []
  var notes: [String] = []
  var counter = 0
  var stepFailures = 0
  var coverage: [String: Int] = [:]
  let sabotage: String

  var habitsViewOpen = false
  var lastActiveHabitIDs: [String]?
  var openHabitID: String?
  var lastHabitDetailRevision: UInt64 = 0
  var memoryViewOpen = false
  var lastMemoryKeys: [String]?
  var calendarLoaded = false

  init(seed: UInt64, sabotage: String) async throws {
    self.sabotage = sabotage
    core = try await makeSeededInMemoryCore()
    store = MobileStore(core: core)
    rng = SplitMix64(state: seed)
    await store.refresh()
    await store.loadDailyReviewDraft()
    lastHabitDetailRevision = store.habitDetailRevision
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

  /// With ENTITY_LOOPBACK set, a step that wrote through the store is followed by
  /// the full refresh the app's own committed-write signal starts about 50 ms
  /// later, so only gaps that refresh cannot close are reported.
  let loopback = ProcessInfo.processInfo.environment["ENTITY_LOOPBACK"] != nil

  /// True for a step that commits a change through a store method. Navigation,
  /// typing, peer and assistant steps are excluded: the last two reload by
  /// themselves. Opening a review day is a write when it saves a dirty draft.
  func writesThroughStore(_ name: String) -> Bool {
    let quiet = [
      "open-calendar", "open-habit", "open-memory", "close-", "select-memory", "edit-memory",
      "new-memory", "edit-review-draft", "refresh", "reload-review", "peer-", "assistant-",
    ]
    return !quiet.contains { name.hasPrefix($0) }
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

  func label(_ ids: [String]) -> [String] { ids.map { String($0.prefix(6)) } }

  func daysAgo(_ k: Int) -> String {
    let today = store.logicalTodayString
    return LorvexDateFormatters.ymdUTCAddingDays(today, days: -k) ?? today
  }

  // MARK: Core reads

  func coreHabits() async -> [LorvexHabit] {
    (try? await core.loadHabits(date: store.logicalTodayString))?.habits ?? []
  }

  func coreArchivedHabits() async -> [LorvexHabit] {
    (try? await core.loadArchivedHabits(date: store.logicalTodayString))?.habits ?? []
  }

  // MARK: Peer changes

  /// A change another device made: the core already holds it, and the store learns
  /// of it the way an inbound CloudKit apply tells it, through the selective reload
  /// of the domains the applied entity kinds map to.
  func inbound(_ kinds: Set<EntityKind>) async {
    if let domains = InboundReloadScope.domains(for: kinds) {
      await store.reloadInboundDomains(domains)
    } else {
      await store.refresh()
    }
  }

  // MARK: Steps

  func buildSteps() async -> [Step] {
    var steps: [Step] = []
    let active = store.habits?.habits ?? []
    let archived = store.archivedHabits
    let lists = store.lists?.lists ?? []
    let entries = store.memory?.entries ?? []
    let coreActive = await coreHabits()
    let coreLists = (try? await core.loadLists())?.lists ?? []
    let coreEntries = (try? await core.loadMemory())?.entries ?? []

    // MARK: habits through the store

    steps.append(
      Step(weight: 6, name: "create-habit") { [self] in
        counter += 1
        var draft = MobileHabitDraft(name: "Habit \(counter)")
        draft.targetCountText = ["1", "1", "2", "3"][Int(rng.next() % 4)]
        switch rng.next() % 4 {
        case 0: break
        case 1:
          draft.cadenceMode = .weekly
          draft.weeklyStyle = .specificDays
          draft.weekdays = [0, 2, 4]
        case 2:
          draft.cadenceMode = .weekly
          draft.weeklyStyle = .timesPerWeek
          draft.timesPerWeek = 3
        default:
          draft.cadenceMode = .monthly
          draft.dayOfMonth = 15
        }
        if chance(3) { draft.milestoneTargetText = "5" }
        trace[trace.count - 1] += " \(draft.cadenceMode) target=\(draft.targetCountText)"
        store.habitDraft = draft
        _ = await store.createDraftHabit()
      })
    if let h = pick(active) {
      steps.append(
        Step(weight: 10, name: "complete-habit \(habitBrief(h))") { [self] in
          _ = await store.completeHabit(h)
        })
      steps.append(
        Step(weight: 4, name: "uncomplete-habit \(habitBrief(h))") { [self] in
          _ = await store.uncompleteHabit(h)
        })
      let k = Int(rng.next() % 5)
      steps.append(
        Step(weight: 4, name: "check-in \(habitBrief(h)) \(k)d ago") { [self] in
          _ = await store.checkInHabit(h, on: daysAgo(k))
        })
      steps.append(
        Step(weight: 3, name: "update-habit \(habitBrief(h))") { [self] in
          counter += 1
          store.prepareHabitDraft(for: h)
          store.habitDraft.name = "Renamed \(counter)"
          if chance(2) { store.habitDraft.targetCountText = "\(1 + Int(rng.next() % 3))" }
          _ = await store.updateHabit(h)
        })
      steps.append(
        Step(weight: 3, name: "archive-habit \(habitBrief(h))") { [self] in
          _ = await store.setHabitArchived(h, archived: true)
        })
      steps.append(
        Step(weight: 2, name: "delete-habit \(habitBrief(h))") { [self] in
          _ = await store.deleteHabit(h)
        })
      steps.append(
        Step(weight: 5, name: "open-habit-detail \(habitBrief(h))") { [self] in
          openHabitID = h.id
          store.selectHabit(h.id)
          _ = await store.loadHabitDetail(id: h.id)
        })
    }
    if !active.isEmpty {
      let ids = pickSome(active, max: 3).map(\.id)
      steps.append(
        Step(weight: 4, name: "batch-complete-habits \(label(ids))") { [self] in
          _ = await store.completeHabits(ids)
        })
      steps.append(
        Step(weight: 3, name: "batch-uncomplete-habits \(label(ids))") { [self] in
          _ = await store.uncompleteHabits(ids)
        })
      steps.append(
        Step(weight: 1, name: "batch-delete-habits \(label(ids))") { [self] in
          _ = await store.deleteHabits(ids)
        })
    }
    if let h = pick(archived) {
      steps.append(
        Step(weight: 4, name: "restore-habit \(habitBrief(h))") { [self] in
          _ = await store.setHabitArchived(h, archived: false)
        })
      steps.append(
        Step(weight: 1, name: "delete-archived-habit \(habitBrief(h))") { [self] in
          _ = await store.deleteHabit(h)
        })
    }
    if openHabitID != nil {
      steps.append(
        Step(weight: 2, name: "close-habit-detail") { [self] in
          openHabitID = nil
          store.selectHabit(nil)
        })
    }
    if let id = openHabitID, active.contains(where: { $0.id == id }) {
      steps.append(
        Step(weight: 3, name: "add-habit-reminder \(id.prefix(6))") { [self] in
          let hour = 6 + Int(rng.next() % 14)
          _ = await store.addHabitReminder(
            habitID: id, time: String(format: "%02d:%02d", hour, Int(rng.next() % 4) * 15))
        })
      if let policy = store.habitDetail(for: id)?.reminderPolicies.first {
        steps.append(
          Step(weight: 2, name: "toggle-habit-reminder \(id.prefix(6))") { [self] in
            _ = await store.toggleHabitReminderEnabled(policy: policy)
          })
        steps.append(
          Step(weight: 2, name: "retime-habit-reminder \(id.prefix(6))") { [self] in
            _ = await store.setHabitReminderTime(policy: policy, to: "21:45")
          })
        steps.append(
          Step(weight: 2, name: "remove-habit-reminder \(id.prefix(6))") { [self] in
            _ = await store.removeHabitReminder(habitID: id, policyID: policy.id)
          })
      }
    }
    steps.append(
      Step(weight: habitsViewOpen ? 1 : 4, name: "open-habits-view") { [self] in
        habitsViewOpen = true
        lastActiveHabitIDs = nil
      })
    if habitsViewOpen {
      steps.append(Step(weight: 1, name: "close-habits-view") { [self] in habitsViewOpen = false })
    }

    // MARK: habits through the assistant

    steps.append(
      Step(weight: 3, name: "assistant-create-habit") { [self] in
        counter += 1
        _ = try? await core.createHabit(
          name: "Assistant habit \(counter)", cue: nil, icon: nil, color: nil, targetCount: 1,
          cadence: .daily, milestoneTarget: nil)
        await store.refresh()
      })
    if let h = pick(coreActive) {
      steps.append(
        Step(weight: 4, name: "assistant-complete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.completeHabit(id: h.id, date: store.logicalTodayString)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "assistant-archive-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: true)
          await store.refresh()
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
        Step(weight: 2, name: "assistant-delete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await store.refresh()
        })
    }
    if let h = pick(await coreArchivedHabits()) {
      steps.append(
        Step(weight: 3, name: "assistant-restore-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: false)
          await store.refresh()
        })
    }

    // MARK: archived habits and the open habit, through the assistant and a peer

    if let h = pick(await coreArchivedHabits()) {
      steps.append(
        Step(weight: 3, name: "assistant-rename-archived-habit \(habitBrief(h))") { [self] in
          counter += 1
          _ = try? await core.updateHabit(
            id: h.id, name: "Archived rename \(counter)", cue: .unset, color: nil, icon: nil,
            targetCount: nil, archived: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "assistant-delete-archived-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-rename-archived-habit \(habitBrief(h))") { [self] in
          counter += 1
          _ = try? await core.updateHabit(
            id: h.id, name: "Peer archived rename \(counter)", cue: .unset, color: nil, icon: nil,
            targetCount: nil, archived: nil)
          await inbound([.habit])
        })
      steps.append(
        Step(weight: 3, name: "peer-delete-archived-habit \(habitBrief(h))") { [self] in
          _ = try? await core.deleteHabit(id: h.id)
          await inbound([.habit])
        })
      steps.append(
        Step(weight: 3, name: "peer-restore-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: false)
          await inbound([.habit])
        })
    }
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
        Step(weight: 4, name: "peer-complete-habit \(habitBrief(h))") { [self] in
          _ = try? await core.completeHabit(id: h.id, date: store.logicalTodayString)
          await inbound([.habitCompletion])
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
        Step(weight: 3, name: "peer-archive-habit \(habitBrief(h))") { [self] in
          _ = try? await core.updateHabit(
            id: h.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
            archived: true)
          await inbound([.habit])
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
    if let id = openHabitID, coreActive.contains(where: { $0.id == id }) {
      steps.append(
        Step(weight: 6, name: "assistant-complete-open-habit \(id.prefix(6))") { [self] in
          _ = try? await core.completeHabit(id: id, date: store.logicalTodayString)
          await store.refresh()
        })
      steps.append(
        Step(weight: 6, name: "peer-complete-open-habit \(id.prefix(6))") { [self] in
          _ = try? await core.completeHabit(id: id, date: store.logicalTodayString)
          await inbound([.habitCompletion])
        })
      steps.append(
        Step(weight: 4, name: "peer-reminder-open-habit \(id.prefix(6))") { [self] in
          let policy = HabitReminderPolicy(
            id: "", habitID: id, habitName: "", reminderTime: "09:30", enabled: true,
            createdAt: "", updatedAt: "")
          _ = try? await core.upsertHabitReminderPolicy(id: id, policy: policy)
          await inbound([.habitReminderPolicy])
        })
    }

    // MARK: lists

    steps.append(
      Step(weight: 3, name: "create-list") { [self] in
        counter += 1
        store.listDraft = MobileListDraft(name: "List \(counter)")
        _ = await store.createDraftList()
      })
    if let l = pick(lists) {
      steps.append(
        Step(weight: 3, name: "update-list \(listBrief(l))") { [self] in
          counter += 1
          store.prepareListDraft(for: l)
          store.listDraft.name = "Renamed list \(counter)"
          _ = await store.updateList(l)
        })
      // Both delete entry points are disabled for the Inbox and for a list that
      // still holds tasks.
      if !l.isInbox, l.totalCount == 0 {
        steps.append(
          Step(weight: 3, name: "delete-list \(listBrief(l))") { [self] in
            _ = await store.deleteList(l)
          })
      }
    }
    steps.append(
      Step(weight: 5, name: "create-task") { [self] in
        counter += 1
        store.captureDraft = MobileCaptureDraft(title: "Entity task \(counter)")
        await store.submitCaptureDraft()
      })
    if let task = pick(store.snapshot.today.tasks) {
      steps.append(
        Step(weight: 4, name: "complete-task \(task.id.prefix(6))") { [self] in
          _ = await store.completeTask(task.id)
        })
      if let l = pick(lists) {
        steps.append(
          Step(weight: 3, name: "move-task \(task.id.prefix(6)) -> \(l.id.prefix(6))") { [self] in
            _ = await store.moveTasks([task.id], toListID: l.id)
          })
      }
    }
    steps.append(
      Step(weight: 2, name: "assistant-create-list") { [self] in
        counter += 1
        _ = try? await core.createList(name: "Assistant list \(counter)", description: nil)
        await store.refresh()
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
      if !l.isInbox {
        steps.append(
          Step(weight: 1, name: "assistant-delete-list \(listBrief(l))") { [self] in
            try? await core.deleteList(id: l.id)
            await store.refresh()
          })
      }
    }

    steps.append(
      Step(weight: 2, name: "peer-create-list") { [self] in
        counter += 1
        _ = try? await core.createList(name: "Peer list \(counter)", description: nil)
        await inbound([.list])
      })
    if let l = pick(coreLists) {
      steps.append(
        Step(weight: 2, name: "peer-rename-list \(listBrief(l))") { [self] in
          counter += 1
          _ = try? await core.updateList(
            id: l.id, name: "Peer list rename \(counter)", description: .unset, color: nil,
            icon: nil)
          await inbound([.list])
        })
      if !l.isInbox, l.totalCount == 0 {
        steps.append(
          Step(weight: 2, name: "peer-delete-list \(listBrief(l))") { [self] in
            try? await core.deleteList(id: l.id)
            await inbound([.list])
          })
      }
    }

    // MARK: memory

    steps.append(
      Step(weight: memoryViewOpen ? 1 : 4, name: "open-memory-view") { [self] in
        memoryViewOpen = true
        lastMemoryKeys = nil
        if store.memory == nil { await store.loadMemorySnapshot() }
      })
    if memoryViewOpen {
      steps.append(Step(weight: 1, name: "close-memory-view") { [self] in memoryViewOpen = false })
    }
    steps.append(
      Step(weight: 4, name: "new-memory") { [self] in
        counter += 1
        store.memoryKeyDraft = "key \(counter)"
        store.memoryContentDraft = "content \(counter)"
        _ = await store.saveMemoryDraft()
      })
    if let e = pick(entries) {
      steps.append(
        Step(weight: 3, name: "edit-memory \(memoryBrief(e))") { [self] in
          counter += 1
          let rename = chance(2)
          _ = await store.saveMemoryEntryEdit(
            originalKey: e.key, newKey: rename ? "key \(counter)" : e.key,
            content: "edited \(counter)")
        })
      steps.append(
        Step(weight: 2, name: "delete-memory \(memoryBrief(e))") { [self] in
          _ = await store.deleteMemoryEntry(e)
        })
      steps.append(
        Step(weight: 3, name: "select-memory \(memoryBrief(e))") { [self] in
          store.selectMemoryEntry(e.id)
        })
    }
    if !entries.isEmpty {
      let batch = pickSome(entries, max: 3)
      steps.append(
        Step(weight: 1, name: "batch-delete-memory \(batch.map(memoryBrief))") { [self] in
          _ = await store.deleteMemoryEntries(batch)
        })
    }
    steps.append(
      Step(weight: 3, name: "assistant-memory-upsert") { [self] in
        counter += 1
        let key = pick(coreEntries)?.key ?? "assistant \(counter)"
        _ = try? await core.upsertMemory(key: chance(2) ? key : "assistant \(counter)", content: "assistant \(counter)")
        await store.refresh()
      })
    if let e = pick(coreEntries) {
      steps.append(
        Step(weight: 1, name: "assistant-memory-delete \(memoryBrief(e))") { [self] in
          _ = try? await core.deleteMemory(key: e.key)
          await store.refresh()
        })
      steps.append(
        Step(weight: 1, name: "assistant-memory-rename \(memoryBrief(e))") { [self] in
          counter += 1
          _ = try? await core.renameMemory(oldKey: e.key, newKey: "renamed \(counter)", content: nil)
          await store.refresh()
        })
    }

    steps.append(
      Step(weight: 3, name: "peer-memory-upsert") { [self] in
        counter += 1
        let key = pick(coreEntries)?.key ?? "peer \(counter)"
        _ = try? await core.upsertMemory(key: chance(2) ? key : "peer \(counter)", content: "peer \(counter)")
        await inbound([.memory])
      })
    if let e = pick(coreEntries) {
      steps.append(
        Step(weight: 2, name: "peer-memory-delete \(memoryBrief(e))") { [self] in
          _ = try? await core.deleteMemory(key: e.key)
          await inbound([.memory])
        })
    }

    // MARK: calendar events

    let events = (store.calendarTimeline?.events ?? []).filter {
      $0.editable && !$0.supportsScopedMutation
    }
    let coreWindowEvents: [CalendarTimelineEvent]
    if let window = store.calendarWindowToReload {
      coreWindowEvents =
        ((try? await core.loadCalendarTimeline(from: window.from, to: window.to))?.events ?? [])
        .filter { $0.editable && !$0.supportsScopedMutation }
    } else {
      coreWindowEvents = []
    }
    steps.append(
      Step(weight: calendarLoaded ? 2 : 5, name: "open-calendar") { [self] in
        let offset = Int(rng.next() % 9) - 4
        await store.refreshCalendarTimeline(
          around: Date().addingTimeInterval(Double(offset) * 86_400))
        calendarLoaded = true
      })
    if calendarLoaded {
      steps.append(
        Step(weight: 5, name: "create-event") { [self] in
          counter += 1
          let start = Date().addingTimeInterval(
            Double(Int(rng.next() % 4)) * 86_400 + Double(1 + Int(rng.next() % 8)) * 3_600)
          let timing =
            chance(4)
            ? CalendarEventTiming(start: start, end: start, allDay: true)
            : CalendarEventTiming.timed(startingAt: start)
          var draft = MobileCalendarDraft(title: "Event \(counter)", timing: timing)
          if chance(3) { draft.location = "Room \(counter)" }
          store.calendarDraft = draft
          trace[trace.count - 1] += " allDay=\(timing.allDay)"
          _ = await store.createDraftCalendarEvent()
        })
      steps.append(
        Step(weight: 3, name: "assistant-create-event") { [self] in
          counter += 1
          let day = LorvexDateFormatters.ymdUTCAddingDays(
            store.logicalTodayString, days: Int(rng.next() % 4)) ?? store.logicalTodayString
          _ = try? await core.createCalendarEvent(
            title: "Assistant event \(counter)", startDate: day, endDate: nil, startTime: "10:00",
            endTime: "11:00", allDay: false, location: nil, notes: nil)
          await store.refresh()
        })
      steps.append(
        Step(weight: 3, name: "peer-create-event") { [self] in
          counter += 1
          let day = LorvexDateFormatters.ymdUTCAddingDays(
            store.logicalTodayString, days: Int(rng.next() % 4)) ?? store.logicalTodayString
          _ = try? await core.createCalendarEvent(
            title: "Peer event \(counter)", startDate: day, endDate: nil, startTime: "14:00",
            endTime: "15:30", allDay: false, location: "Peer room", notes: nil)
          await inbound([.calendarEvent])
        })
    }
    if let ev = pick(events) {
      steps.append(
        Step(weight: 4, name: "update-event \(eventBrief(ev))") { [self] in
          counter += 1
          store.prepareCalendarDraft(for: ev)
          store.calendarDraft.title = "Edited event \(counter)"
          if chance(2) {
            let shifted = store.calendarDraft.timing.start.addingTimeInterval(
              Double(1 + Int(rng.next() % 3)) * 86_400)
            store.calendarDraft.timing = .timed(startingAt: shifted)
          }
          _ = await store.updateCalendarEvent(ev)
        })
      steps.append(
        Step(weight: 3, name: "reschedule-event \(eventBrief(ev))") { [self] in
          let start = CalendarEventTiming(event: ev, fallbackDay: Date()).start
            .addingTimeInterval(Double(1 + Int(rng.next() % 5)) * 3_600)
          _ = await store.rescheduleCalendarEvent(
            ev, newStart: start, newEnd: start.addingTimeInterval(3_600))
        })
      steps.append(
        Step(weight: 3, name: "delete-event \(eventBrief(ev))") { [self] in
          _ = await store.deleteCalendarEvent(ev)
        })
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

    // MARK: daily review

    let k = Int(rng.next() % 5)
    steps.append(
      Step(weight: 4, name: "open-review-day \(k)d ago") { [self] in
        await store.selectReviewDay(daysAgo(k))
      })
    steps.append(
      Step(weight: 5, name: "edit-review-draft") { [self] in
        counter += 1
        switch rng.next() % 5 {
        case 0: store.dailyReviewDraft.summary = chance(3) ? "" : "Summary \(counter)"
        case 1: store.dailyReviewDraft.wins = "Win \(counter)"
        case 2: store.dailyReviewDraft.mood = chance(4) ? nil : 1 + Int(rng.next() % 5)
        case 3: store.dailyReviewDraft.energy = chance(4) ? nil : 1 + Int(rng.next() % 5)
        default: store.dailyReviewDraft.learnings = "Learned \(counter)"
        }
        trace[trace.count - 1] += " editable=\(store.selectedReviewDayIsEditable)"
      })
    steps.append(
      Step(weight: 3, name: "save-review") { [self] in
        trace[trace.count - 1] +=
          " canSave=\(store.dailyReviewDraft.canSave) editable=\(store.selectedReviewDayIsEditable)"
        _ = await store.saveDailyReviewDraft()
      })
    steps.append(
      Step(weight: 3, name: "flush-review") { [self] in
        trace[trace.count - 1] +=
          " clean=\(store.dailyReviewDraftMatchesLoaded) editable=\(store.selectedReviewDayIsEditable)"
        await store.flushAutosaveDraftsBeforeSuspension()
      })
    steps.append(
      Step(weight: 1, name: "reload-review") { [self] in
        await store.loadDailyReviewDraft()
      })
    steps.append(
      Step(weight: 2, name: "assistant-review") { [self] in
        counter += 1
        let date = chance(2) ? store.selectedReviewDate : store.logicalTodayString
        trace[trace.count - 1] += " \(date)"
        _ = try? await core.upsertDailyReview(
          date: date, summary: "Assistant \(counter)", mood: 3, energyLevel: 4, wins: "aw",
          blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
        await store.refresh()
      })
    steps.append(
      Step(weight: 2, name: "peer-review") { [self] in
        counter += 1
        let date = chance(2) ? store.selectedReviewDate : store.logicalTodayString
        trace[trace.count - 1] += " \(date)"
        _ = try? await core.upsertDailyReview(
          date: date, summary: "Peer \(counter)", mood: 2, energyLevel: 5, wins: "pw",
          blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
        await inbound([.dailyReview])
      })
    steps.append(
      Step(weight: 3, name: "refresh") { [self] in
        await store.refresh()
      })
    return steps
  }

  // MARK: View triggers

  /// What the views do on their own once the store state changed.
  func settleViews() async {
    if habitsViewOpen {
      let ids = (store.habits?.habits ?? []).map(\.id)
      if ids != lastActiveHabitIDs {
        lastActiveHabitIDs = ids
        if let selected = store.selectedHabitID, !ids.contains(selected) {
          store.selectHabit(nil)
        }
        if sabotage != "archived" { await store.loadArchivedHabits() }
      }
    }
    if memoryViewOpen {
      let keys = (store.memory?.entries ?? []).map(\.key)
      if keys != lastMemoryKeys {
        lastMemoryKeys = keys
        if let selected = store.selectedMemoryKey, !keys.contains(selected) {
          store.selectMemoryEntry(nil)
        }
      }
    }
    if let id = openHabitID {
      if store.habits?.habits.contains(where: { $0.id == id }) == true {
        if sabotage != "detail",
          store.habitDetailRevision != lastHabitDetailRevision || store.habitDetail(for: id) == nil
        {
          _ = await store.loadHabitDetail(id: id)
        }
      } else {
        openHabitID = nil
      }
    }
    lastHabitDetailRevision = store.habitDetailRevision
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
    let haveHabits = (store.habits?.habits ?? []).map(habitBrief)
    if wantHabits != haveHabits {
      let missing = Set(wantHabits).subtracting(haveHabits).sorted()
      let extra = Set(haveHabits).subtracting(wantHabits).sorted()
      fail("habits-stale", "missing \(missing) extra \(extra) orderSame=\(Set(wantHabits) == Set(haveHabits))")
    }
    if habitsViewOpen {
      coverage["data.habitsViewChecks", default: 0] += 1
      let wantArchived = await coreArchivedHabits().map(archivedBrief)
      let haveArchived = store.archivedHabits.map(archivedBrief)
      if !haveArchived.isEmpty { coverage["data.archivedNonEmpty", default: 0] += 1 }
      if wantArchived != haveArchived {
        let missing = Set(wantArchived).subtracting(haveArchived).sorted()
        let extra = Set(haveArchived).subtracting(wantArchived).sorted()
        fail("archived-stale", "missing \(missing) extra \(extra)")
      }
      if let selected = store.selectedHabitID,
        store.habits?.habits.contains(where: { $0.id == selected }) != true
      {
        fail("selected-habit-dangling", "\(selected.prefix(6))")
      }
    }
    if let id = openHabitID {
      coverage["data.detailOpenChecks", default: 0] += 1
      await checkHabitDetail(id)
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

    // Memory.
    if let shown = store.memory?.entries, let fresh = try? await core.loadMemory() {
      coverage["data.memoryChecks", default: 0] += 1
      if !shown.isEmpty { coverage["data.memoryNonEmpty", default: 0] += 1 }
      let want = fresh.entries.map(memoryBrief)
      let have = shown.map(memoryBrief)
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("memory-stale", "missing \(missing) extra \(extra)")
      }
      if memoryViewOpen, let selected = store.selectedMemoryKey,
        !fresh.entries.contains(where: { $0.key == selected })
      {
        fail("selected-memory-dangling", selected)
      }
    }

    // Calendar events: the loaded window equals a fresh read of itself.
    if calendarLoaded, let window = store.calendarWindowToReload,
      let fresh = try? await core.loadCalendarTimeline(from: window.from, to: window.to)
    {
      coverage["data.calendarChecks", default: 0] += 1
      if !fresh.events.isEmpty { coverage["data.calendarNonEmpty", default: 0] += 1 }
      // An event moved or created past the window's edge stays in the list until
      // the next window load; the day grids draw only days inside the window.
      let inWindow: (CalendarTimelineEvent) -> Bool = {
        $0.startDate <= window.to && ($0.endDate ?? $0.startDate) >= window.from
      }
      let want = fresh.events.filter(inWindow).map(eventBrief).sorted()
      let have = (store.calendarTimeline?.events ?? []).filter(inWindow).map(eventBrief).sorted()
      if want != have {
        let missing = Set(want).subtracting(have).sorted()
        let extra = Set(have).subtracting(want).sorted()
        fail("calendar-events-stale", "missing \(missing) extra \(extra)")
      }
    }

    // Daily review: a clean editor shows exactly what the core holds.
    if let fresh = try? await core.loadDailyReview(date: store.selectedReviewDate) {
      coverage["data.reviewSaved", default: 0] += 1
      if store.dailyReviewDraftMatchesLoaded {
        if store.dailyReview != fresh {
          fail(
            "review-stale",
            "store \(reviewBrief(store.dailyReview)) core \(reviewBrief(fresh)) day \(store.selectedReviewDate)"
          )
        }
      } else if store.dailyReview != fresh {
        notes.append(
          "step \(trace.count): dirty draft over a loaded review that differs from the core: store \(reviewBrief(store.dailyReview)) core \(reviewBrief(fresh))"
        )
      }
    }
  }

  func checkHabitDetail(_ id: String) async {
    let to = store.logicalTodayString
    let from = LorvexDateFormatters.ymdUTCAddingDays(to, days: -(16 * 7)) ?? to
    guard let stats = try? await core.getHabitStats(id: id),
      let completions = try? await core.getHabitCompletions(id: id, from: from, to: to, limit: 400),
      let policies = try? await core.getHabitReminderPolicies(id: id)
    else { return }
    guard let shown = store.habitDetail(for: id) else {
      return fail("habit-detail-missing", "\(id.prefix(6))")
    }
    if shown.stats != stats {
      fail("habit-detail-stats-stale", "store \(shown.stats) core \(stats)")
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
        await store.loadArchivedHabits()
        await store.loadMemorySnapshot()
        await store.loadDailyReviewDraft()
        lastActiveHabitIDs = nil
        lastMemoryKeys = nil
        await settleViews()
      }
    }
  }
}

@MainActor
@Test
func zzMobileEntityWalkProbe() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let seed = env["ENTITY_SEED"].flatMap(UInt64.init) else { return }
  let steps = env["ENTITY_STEPS"].flatMap(Int.init) ?? 60
  let walk = try await EntityWalk(seed: seed, sabotage: env["ENTITY_SABOTAGE"] ?? "")
  await walk.run(steps: steps)
  print(
    "EWALK seed=\(seed) steps=\(walk.trace.count) failures=\(walk.failures.count) notes=\(walk.notes.count)"
  )
  for note in walk.notes.prefix(12) { print("EWALK note \(note)") }
  if env["ENTITY_COVERAGE"] != nil {
    for (key, count) in walk.coverage.sorted(by: { $0.key < $1.key }) {
      print("EWALK coverage \(key)=\(count)")
    }
  }
  if !walk.failures.isEmpty {
    if env["ENTITY_TRACE"] != nil {
      for (index, line) in walk.trace.enumerated() { print("EWALK trace \(index + 1): \(line)") }
    }
    for failure in walk.failures { print("EWALK FAIL seed=\(seed) \(failure)") }
  }
}
