import Foundation
import LorvexStore
import Testing

@testable import LorvexCore

/// Core service contract suite: end-to-end query/write semantics of
/// `SwiftLorvexCoreService` over an in-memory GRDB store running the repo's
/// canonical `schema/schema.sql` — sort keys, filter buckets, status
/// transitions, patch semantics, pagination, and window math. Each contract
/// operates exclusively on rows it creates (tagged with a unique marker), so
/// it holds regardless of seed data.
@Suite("Core service contract")
struct CoreServiceContractTests {
  private func makeService() throws -> any LorvexCoreServicing {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schema))
  }

  private func tasks(
    _ service: any LorvexCoreServicing, status: String, marker: String
  ) async throws -> [LorvexTask] {
    try await service.listTasks(
      status: status, listID: nil, priority: nil, text: marker, limit: 50, offset: 0
    ).tasks
  }

  @Test("createTask round-trips through listTasks as an open task")
  func createRoundTrips() async throws {
    let service = try makeService()
    let marker = "contract-create-\(UUID().uuidString.prefix(8))"

    let created = try await service.createTask(title: "Task \(marker)", notes: "")

    let listed = try await tasks(service, status: "all", marker: marker)
    let found = try #require(listed.first { $0.id == created.id })
    #expect(found.title == "Task \(marker)")
    #expect(found.status == .open)
  }

  @Test("completeTask transitions the status filter buckets")
  func completeTransitions() async throws {
    let service = try makeService()
    let marker = "contract-complete-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")

    _ = try await service.completeTask(id: created.id)

    let completed = try await tasks(service, status: "completed", marker: marker)
    #expect(completed.contains { $0.id == created.id })
    let open = try await tasks(service, status: "open", marker: marker)
    #expect(!open.contains { $0.id == created.id })
  }

  @Test("updateTask persists the title and priority")
  func updatePersists() async throws {
    let service = try makeService()
    let marker = "contract-update-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Before \(marker)", notes: "")

    _ = try await service.updateTask(
      id: created.id, title: "After \(marker)", notes: "now with notes",
      priority: .p1, estimatedMinutes: nil, plannedDate: nil, tags: [], dependsOn: [])

    let listed = try await tasks(service, status: "all", marker: marker)
    let found = try #require(listed.first { $0.id == created.id })
    #expect(found.title == "After \(marker)")
    #expect(found.priority == .p1)
  }

  @Test(
    "markTaskSomeday sets status=someday and keeps the task's list")
  func markSomedayKeepsList() async throws {
    let service = try makeService()
    let marker = "contract-someday-\(UUID().uuidString.prefix(8))"
    let list = try await service.createList(name: "List \(marker)", description: nil)
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    _ = try await service.moveTask(id: created.id, toListID: list.id)

    let parked = try await service.markTaskSomeday(id: created.id)

    // Status flips to someday; list membership is orthogonal and untouched.
    #expect(parked.status == .someday)
    #expect(parked.listID == list.id)

    // It leaves the open bucket and lands in the someday bucket.
    let open = try await tasks(service, status: "open", marker: marker)
    #expect(!open.contains { $0.id == created.id })
    let someday = try await tasks(service, status: "someday", marker: marker)
    #expect(someday.contains { $0.id == created.id })

    // Membership also projects through the single-task read.
    let loaded = try await service.loadTask(id: created.id)
    #expect(loaded.listID == list.id)
    #expect(loaded.status == .someday)

    // The weekly review surfaces the parked task in its someday peek, distinct
    // from the bare count.
    let review = try await service.loadWeeklyReview()
    #expect(review.someday >= 1)
    #expect(review.topSomeday.contains { $0.id == created.id })
  }

  @Test(
    "due_date and planned_date are independent, settable, and clearable")
  func dueDateIndependentFromPlannedDate() async throws {
    let service = try makeService()
    let marker = "contract-duedate-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    let due = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-07-01"))
    let planned = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-20"))

    // Setting only due_date leaves planned_date null.
    let onlyDue = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: nil, dueDate: due, plannedDate: nil, tags: [], dependsOn: [])
    #expect(onlyDue.dueDate == due)
    #expect(onlyDue.plannedDate == nil)

    // Setting only planned_date leaves due_date null (and vice versa).
    let onlyPlanned = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: nil, dueDate: nil, plannedDate: planned, tags: [], dependsOn: [])
    #expect(onlyPlanned.dueDate == nil)
    #expect(onlyPlanned.plannedDate == planned)

    // Both settable together; the single-task read agrees with the write echo.
    let both = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: nil, dueDate: due, plannedDate: planned, tags: [], dependsOn: [])
    #expect(both.dueDate == due)
    #expect(both.plannedDate == planned)
    let loaded = try await service.loadTask(id: created.id)
    #expect(loaded.dueDate == due)
    #expect(loaded.plannedDate == planned)
  }

  @Test(
    "updateTask(_:) patches only supplied fields, leaving omitted columns untouched")
  func updateTaskDraftPatchSemantics() async throws {
    let service = try makeService()
    let marker = "contract-patch-\(UUID().uuidString.prefix(8))"
    let due = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-07-01"))
    let planned = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-06-20"))
    let created = try await service.createTask(
      TaskCreateDraft(
        title: "Task \(marker)", notes: "original notes", priority: .p1,
        estimatedMinutes: 45, dueDate: due, plannedDate: planned, tags: [marker]))

    // Patch ONLY the title: every other column is `.unset`, so a concurrent
    // writer's value for it (modelled here by the create) must survive rather
    // than be force-written from a stale read-modify-write snapshot.
    let renamed = try await service.updateTask(
      TaskUpdateDraft(id: created.id, title: "Renamed \(marker)"))
    #expect(renamed.title == "Renamed \(marker)")
    #expect(renamed.notes == "original notes")
    #expect(renamed.priority == .p1)
    #expect(renamed.estimatedMinutes == 45)
    #expect(renamed.dueDate == due)
    #expect(renamed.plannedDate == planned)
    #expect(renamed.tags == created.tags)

    // A supplied `.clear` clears that one column; the still-omitted columns
    // stay put.
    let cleared = try await service.updateTask(
      TaskUpdateDraft(id: created.id, estimatedMinutes: .clear, plannedDate: .clear))
    #expect(cleared.estimatedMinutes == nil)
    #expect(cleared.plannedDate == nil)
    #expect(cleared.title == "Renamed \(marker)")
    #expect(cleared.notes == "original notes")
    #expect(cleared.dueDate == due)
    #expect(cleared.tags == created.tags)
  }

  @Test(
    "returning-task status mutations echo the mutated task in one step")
  func statusMutationReturningTaskVariants() async throws {
    let service = try makeService()
    let marker = "contract-return-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")

    let completed = try await service.completeTaskReturningTask(id: created.id)
    #expect(completed.id == created.id)
    #expect(completed.status == .completed)

    let reopened = try await service.reopenTaskReturningTask(id: created.id)
    #expect(reopened.status == .open)

    let planned = try #require(LorvexDateFormatters.ymdUTC.date(from: "2027-02-01"))
    let deferred = try await service.deferTaskReturningTask(
      id: created.id, until: planned, reason: nil)
    #expect(deferred.plannedDate == planned)
    #expect(deferred.status == .open)

    let cancelled = try await service.cancelTaskReturningTask(id: created.id)
    #expect(cancelled.status == .cancelled)
  }

  @Test(
    "batchCancelTasksInList returns the full cancelled tasks")
  func batchCancelInListReturnsTasks() async throws {
    let service = try makeService()
    let marker = "contract-cancelinlist-\(UUID().uuidString.prefix(8))"
    let list = try await service.createList(name: "List \(marker)", description: nil)
    let first = try await service.createTask(
      TaskCreateDraft(title: "First \(marker)", listID: list.id))
    let second = try await service.createTask(
      TaskCreateDraft(title: "Second \(marker)", listID: list.id))

    let cancelled = try await service.batchCancelTasksInList(
      listID: list.id, statuses: ["open"], cancelSeries: false)

    #expect(Set(cancelled.map(\.id)) == [first.id, second.id])
    #expect(cancelled.allSatisfy { $0.status == .cancelled })
  }

  @Test(
    "batchCompleteTasks returns the changed tasks and skips the rest")
  func batchCompleteReturnsChangedTasks() async throws {
    let service = try makeService()
    let marker = "contract-batchdone-\(UUID().uuidString.prefix(8))"
    let first = try await service.createTask(title: "First \(marker)", notes: "")
    let second = try await service.createTask(title: "Second \(marker)", notes: "")

    let result = try await service.batchCompleteTasks(ids: [first.id, second.id, "missing-\(marker)"])

    #expect(Set(result.changedIDs) == [first.id, second.id])
    #expect(result.skipped == ["missing-\(marker)"])
    // The enriched tasks travel with the result (captured in-transaction), one
    // per changed id, each reflecting the completed status.
    #expect(result.changedTasks.count == result.changedIDs.count)
    #expect(Set(result.changedTasks.map(\.id)) == Set(result.changedIDs))
    #expect(result.changedTasks.allSatisfy { $0.status == .completed })
  }

  @Test("cancelTask lands the task in the cancelled bucket")
  func cancelTransitions() async throws {
    let service = try makeService()
    let marker = "contract-cancel-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")

    _ = try await service.cancelTask(id: created.id)

    let cancelled = try await tasks(service, status: "cancelled", marker: marker)
    #expect(cancelled.contains { $0.id == created.id })
    let open = try await tasks(service, status: "open", marker: marker)
    #expect(!open.contains { $0.id == created.id })
  }

  @Test(
    "listTasks pagination reports totalMatching, truncation, and nextOffset")
  func paginationContract() async throws {
    let service = try makeService()
    let marker = "contract-page-\(UUID().uuidString.prefix(8))"
    for index in 1...5 {
      _ = try await service.createTask(title: "Task \(index) \(marker)", notes: "")
    }

    let firstPage = try await service.listTasks(
      status: "all", listID: nil, priority: nil, text: marker, limit: 2, offset: 0)
    #expect(firstPage.returned == 2)
    #expect(firstPage.tasks.count == 2)
    #expect(firstPage.totalMatching == 5)
    #expect(firstPage.truncated)
    #expect(firstPage.nextOffset == 2)

    let lastPage = try await service.listTasks(
      status: "all", listID: nil, priority: nil, text: marker, limit: 2, offset: 4)
    #expect(lastPage.returned == 1)
    #expect(lastPage.totalMatching == 5)
    #expect(!lastPage.truncated)
    #expect(lastPage.nextOffset == nil)
  }

  @Test(
    "habit completion accumulates; uncomplete resets the whole day")
  func habitCompletionRoundTrips() async throws {
    let service = try makeService()
    let date = "2026-01-15"
    let created = try await service.createHabit(
      name: "Contract habit \(UUID().uuidString.prefix(8))", cue: nil, targetCount: 2)

    _ = try await service.completeHabit(id: created.id, date: date)
    let afterTwo = try await service.completeHabit(id: created.id, date: date)
    let completedTwice = try #require(afterTwo.habits.first { $0.id == created.id })
    #expect(completedTwice.completionsToday == 2)

    // `uncompleteHabit` is the "Reset today" action: it clears every
    // completion for the date, not just the most recent one.
    let afterReset = try await service.uncompleteHabit(id: created.id, date: date)
    let reset = try #require(afterReset.habits.first { $0.id == created.id })
    #expect(reset.completionsToday == 0)
  }

  @Test(
    "getWeeklyReviewSnapshot windows completions to the requested week")
  func weeklyReviewWindowHonorsWeekOf() async throws {
    let service = try makeService()
    let marker = "contract-week-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    _ = try await service.completeTask(id: created.id)

    // The window is computed in the store's configured timezone; near
    // midnight the local and UTC calendar days differ, so query both and
    // require the completion to land in at least one of them.
    func ymd(_ zone: TimeZone) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.timeZone = zone
      formatter.locale = Locale(identifier: "en_US_POSIX")
      return formatter.string(from: Date())
    }
    let localWeek = try await service.getWeeklyReviewSnapshot(weekOf: ymd(.current))
    let utcWeek = try await service.getWeeklyReviewSnapshot(
      weekOf: ymd(TimeZone(secondsFromGMT: 0) ?? .current))
    #expect(max(localWeek.completedThisWeek, utcWeek.completedThisWeek) >= 1)

    // A week from years before the store existed has no completions, and its
    // window is visibly the requested one.
    let pastWeek = try await service.getWeeklyReviewSnapshot(weekOf: "2019-01-15")
    #expect(pastWeek.completedThisWeek == 0)
    #expect(pastWeek.windowTitle.contains("2019-01-15"))
    #expect(pastWeek.windowTitle != localWeek.windowTitle)
  }

  @Test(
    "loadDaySummary attributes a completion to its day and clamps the limit")
  func loadDaySummaryAttributesCompletion() async throws {
    let service = try makeService()
    let marker = "contract-day-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    _ = try await service.completeTask(id: created.id)

    // The day window is computed in the store's configured timezone; near
    // midnight the local and UTC calendar days differ, so query both and
    // require the completion to land in at least one of them.
    func ymd(_ zone: TimeZone) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      formatter.timeZone = zone
      formatter.locale = Locale(identifier: "en_US_POSIX")
      return formatter.string(from: Date())
    }
    let local = try await service.loadDaySummary(date: ymd(.current))
    let utc = try await service.loadDaySummary(date: ymd(TimeZone(secondsFromGMT: 0) ?? .current))
    let landed =
      local.topCompleted.contains { $0.id == created.id }
      || utc.topCompleted.contains { $0.id == created.id }
    #expect(landed)
    #expect(max(local.completedCount, utc.completedCount) >= 1)

    // A day years before the store existed has no evidence.
    let past = try await service.loadDaySummary(date: "2019-01-15")
    #expect(past.completedCount == 0)
    #expect(past.dueOpenCount == 0)
    #expect(past.topCompleted.isEmpty)

    // The completed cap clamps to 1...50; an out-of-range value is clamped,
    // never rejected.
    let clamped = try await service.loadDaySummary(date: ymd(.current), completedLimit: 1000)
    #expect(clamped.topCompleted.count <= 50)
  }

  @Test(
    "getWeeklyReviewBrief honors and reports section limits")
  func weeklyBriefHonorsSectionLimits() async throws {
    let service = try makeService()
    let marker = "contract-brief-\(UUID().uuidString.prefix(8))"
    for index in 1...3 {
      let created = try await service.createTask(title: "Task \(index) \(marker)", notes: "")
      _ = try await service.completeTask(id: created.id)
    }

    // An explicit limit truncates the section and is reported back in meta —
    // the tool may never advertise a knob it silently ignores.
    let limited = try await service.getWeeklyReviewBrief(
      completedLimit: 2, stalledListsLimit: nil, deferredLimit: nil, somedayLimit: nil)
    #expect(limited.completedThisWeek.count == 2)
    #expect(limited.sectionMeta.completedThisWeek.limit == 2)
    #expect(limited.sectionMeta.completedThisWeek.totalMatching >= 3)
    #expect(limited.sectionMeta.completedThisWeek.truncated)

    // Nil takes the shared default, also reported honestly.
    let defaulted = try await service.getWeeklyReviewBrief(
      completedLimit: nil, stalledListsLimit: nil, deferredLimit: nil, somedayLimit: nil)
    #expect(
      defaulted.sectionMeta.completedThisWeek.limit
        == WeeklyReviewBriefLimitPolicy.completedDefault)
    #expect(defaulted.completedThisWeek.count >= 3)
  }

  @Test(
    "proposeFocusSchedule honors working-hours overrides")
  func scheduleProposalHonorsWorkingHours() async throws {
    let service = try makeService()
    let marker = "contract-sched-hours-\(UUID().uuidString.prefix(8))"
    let date = "2026-03-04"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    _ = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: 60, plannedDate: nil, tags: [], dependsOn: [])
    _ = try await service.setCurrentFocus(
      date: date, taskIDs: [created.id], briefing: nil, timezone: TimeZone.current.identifier)

    // The override moves the whole proposal window: blocks start at the
    // requested opening and the response reports the applied hours.
    let custom = try await service.proposeFocusSchedule(
      date: date, workingHoursStart: "10:00", workingHoursEnd: "12:00",
      includeCalendarEvents: false)
    #expect(custom.workingHours?.start == "10:00")
    #expect(custom.workingHours?.end == "12:00")
    #expect(custom.blocks.first?.startTime == "10:00")

    // An invalid override is rejected, not silently ignored.
    await #expect(throws: (any Error).self) {
      _ = try await service.proposeFocusSchedule(
        date: date, workingHoursStart: "25:99", workingHoursEnd: nil,
        includeCalendarEvents: nil)
    }
  }

  @Test(
    "the stored working_hours preference drives the schedule proposal")
  func scheduleProposalReadsWorkingHoursPreference() async throws {
    let service = try makeService()
    let marker = "contract-pref-hours-\(UUID().uuidString.prefix(8))"
    let date = "2026-03-05"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    _ = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: 30, plannedDate: nil, tags: [], dependsOn: [])
    _ = try await service.setCurrentFocus(
      date: date, taskIDs: [created.id], briefing: nil, timezone: TimeZone.current.identifier)

    _ = try await service.setPreference(
      key: "working_hours", value: #"{"start":"08:30","end":"16:00"}"#)

    let proposal = try await service.proposeFocusSchedule(date: date)
    #expect(proposal.workingHours?.start == "08:30")
    #expect(proposal.workingHours?.end == "16:00")
    #expect(proposal.blocks.first?.startTime == "08:30")
  }

  @Test(
    "habit reminder policies round-trip through the bulk read")
  func habitReminderPoliciesBulkRead() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Reminder habit \(UUID().uuidString.prefix(8))", cue: nil, targetCount: 1)
    // An empty policy id is the create form (the backend generates the id);
    // a non-empty id must already exist.
    let policy = HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: habit.name,
      reminderTime: "07:45", enabled: true, createdAt: "", updatedAt: "")
    let created = try await service.upsertHabitReminderPolicy(id: habit.id, policy: policy)
    #expect(!created.id.isEmpty)

    let all = try await service.getAllHabitReminderPolicies()
    let found = try #require(all.first { $0.habitID == habit.id })
    #expect(found.reminderTime == "07:45")
    #expect(found.enabled)

    // Delete returns the removed policy; a second delete of the same id is
    // an idempotent nil, and the bulk read no longer lists it.
    let removed = try await service.deleteHabitReminderPolicy(policyID: found.id)
    #expect(removed?.id == found.id)
    let again = try await service.deleteHabitReminderPolicy(policyID: found.id)
    #expect(again == nil)
    let remaining = try await service.getAllHabitReminderPolicies()
    #expect(!remaining.contains { $0.id == found.id })
  }

  @Test(
    "getDueHabitReminderOccurrences expands a daily policy then suppresses a met day")
  func habitDueReminderOccurrences() async throws {
    let service = try makeService()
    // Pin the store to the system zone so its wall-clock fire instants bucket
    // the same calendar days the test computes below.
    _ = try await service.setPreference(
      key: "timezone", value: "\"\(TimeZone.current.identifier)\"")
    let habit = try await service.createHabit(
      name: "Hydrate \(UUID().uuidString.prefix(8))", cue: nil, targetCount: 1)
    _ = try await service.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name, reminderTime: "23:59", enabled: true,
        createdAt: "", updatedAt: ""))

    // A daily habit yields one future occurrence per day in the horizon.
    let now = Date()
    let before = try await service.getDueHabitReminderOccurrences(now: now, horizonDays: 5)
    let mine = before.filter { $0.policy.habitID == habit.id }
    #expect(!mine.isEmpty)
    #expect(mine.allSatisfy { $0.fireDate > now })

    // Completing the habit for every horizon day meets each day's target of 1,
    // so the policy contributes no occurrence on the next plan.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    for offset in 0...5 {
      let day = cal.date(byAdding: .day, value: offset, to: now) ?? now
      let c = cal.dateComponents([.year, .month, .day], from: day)
      let ymd = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
      _ = try await service.completeHabit(id: habit.id, date: ymd)
    }
    let after = try await service.getDueHabitReminderOccurrences(now: now, horizonDays: 5)
    #expect(!after.contains { $0.policy.habitID == habit.id })
  }

  @Test(
    "importDailyReview accepts historical dates; the interactive upsert does not")
  func importBypassesReviewWriteWindow() async throws {
    let service = try makeService()

    // Restore path: a backup legitimately carries reviews far older than the
    // interactive write window.
    let imported = try await service.importDailyReview(
      date: "2020-03-01", summary: "Restored from backup", mood: 4, energyLevel: 3,
      wins: nil, blockers: nil, learnings: nil,
      timezone: nil, updatedAt: nil, linkedTaskIDs: nil, linkedListIDs: nil)
    #expect(imported.date == "2020-03-01")
    let history = try await service.getReviewHistory(
      from: "2020-03-01", to: "2020-03-01", limit: 5)
    #expect(history.contains { $0.date == "2020-03-01" && $0.summary == "Restored from backup" })

    // Interactive path: the staleness window still rejects the same date.
    await #expect(throws: (any Error).self) {
      _ = try await service.upsertDailyReviewPreservingLinks(
        date: "2020-03-01", summary: "Stale interactive write", mood: nil, energyLevel: nil,
        wins: nil, blockers: nil, learnings: nil)
    }
  }

  @Test("listTasks filters by listID after moveTask")
  func listScopeFilter() async throws {
    let service = try makeService()
    let marker = "contract-scope-\(UUID().uuidString.prefix(8))"
    let list = try await service.createList(name: "List \(marker)", description: nil)
    let inside = try await service.createTask(title: "In \(marker)", notes: "")
    _ = try await service.createTask(title: "Out \(marker)", notes: "")
    _ = try await service.moveTask(id: inside.id, toListID: list.id)

    let scoped = try await service.listTasks(
      status: "all", listID: list.id, priority: nil, text: marker, limit: 50, offset: 0)
    #expect(scoped.tasks.map(\.id) == [inside.id])

    // Membership also projects through the single-task read, not only the
    // scoped list query.
    let loaded = try await service.loadTask(id: inside.id)
    #expect(loaded.listID == list.id)
  }

  @Test("memory upsert round-trips, overwrites, and deletes")
  func memoryRoundTrip() async throws {
    let service = try makeService()
    let key = "contract-memory-\(UUID().uuidString.prefix(8))"

    _ = try await service.upsertMemory(key: key, content: "first value")
    var snapshot = try await service.loadMemory()
    #expect(snapshot.entries.contains { $0.key == key && $0.content == "first value" })

    _ = try await service.upsertMemory(key: key, content: "second value")
    snapshot = try await service.loadMemory()
    #expect(snapshot.entries.contains { $0.key == key && $0.content == "second value" })
    #expect(snapshot.entries.filter { $0.key == key }.count == 1, "upsert overwrites, never duplicates")

    _ = try await service.deleteMemory(key: key)
    snapshot = try await service.loadMemory()
    #expect(!snapshot.entries.contains { $0.key == key })
  }

  @Test(
    "calendar event lifecycle: create renders in the timeline, update patches, delete removes")
  func calendarEventLifecycle() async throws {
    let service = try makeService()
    let marker = "contract-event-\(UUID().uuidString.prefix(8))"

    let created = try await service.createCalendarEvent(
      title: "Event \(marker)", startDate: "2026-03-05", endDate: nil,
      startTime: "14:00", endTime: "15:00", allDay: false,
      location: "HQ", notes: nil)
    let timeline = try await service.loadCalendarTimeline(from: "2026-03-01", to: "2026-03-08")
    let listed = try #require(timeline.events.first { $0.id == created.id })
    #expect(listed.title == "Event \(marker)")
    #expect(listed.startTime == "14:00")
    #expect(listed.location == "HQ")

    // Patch semantics: nil fields stay untouched.
    let updated = try await service.updateCalendarEvent(
      id: created.id, title: "Renamed \(marker)", startDate: nil, endDate: nil,
      startTime: nil, endTime: nil, allDay: nil, location: nil, notes: nil,
      recurrence: .unset, timezone: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: .unset)
    #expect(updated.title == "Renamed \(marker)")
    #expect(updated.startTime == "14:00", "nil patch fields must stay untouched")
    #expect(updated.location == "HQ")

    try await service.deleteCalendarEvent(id: created.id)
    let after = try await service.loadCalendarTimeline(from: "2026-03-01", to: "2026-03-08")
    #expect(!after.events.contains { $0.id == created.id })
  }

  @Test(
    "removing a calendar-event exception restores the skipped occurrence")
  func removeEventExceptionRestoresOccurrence() async throws {
    let service = try makeService()
    let marker = "contract-exdate-\(UUID().uuidString.prefix(8))"
    let created = try await service.createCalendarEvent(
      title: "Standup \(marker)", startDate: "2026-03-02", endDate: "2026-03-02",
      startTime: "09:00", endTime: "09:15", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY"}"#),
      timezone: nil, url: nil, color: nil,
      eventType: nil, personName: nil, attendees: nil)

    _ = try await service.addCalendarEventException(eventID: created.id, date: "2026-03-04")
    let skipped = try await service.loadCalendarTimeline(from: "2026-03-04", to: "2026-03-04")
    #expect(!skipped.events.contains { $0.eventID == created.id })
    _ = try await service.removeCalendarEventException(eventID: created.id, date: "2026-03-04")
    let restored = try await service.loadCalendarTimeline(from: "2026-03-04", to: "2026-03-04")
    #expect(
      restored.events.contains {
        $0.eventID == created.id && $0.occurrenceDate == "2026-03-04"
      })
  }

  @Test(
    "a planned task appears in the scheduled window on its planned day")
  func plannedTaskAppearsInScheduledWindow() async throws {
    let service = try makeService()
    let marker = "contract-sched-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(title: "Task \(marker)", notes: "")
    let plannedDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-04-15"))
    _ = try await service.updateTask(
      id: created.id, title: created.title, notes: "", priority: created.priority,
      estimatedMinutes: nil, plannedDate: plannedDay, tags: [], dependsOn: [])

    // The calendar lane's day is planned-first (reference product:
    // `task.planned_date ?? task.due_date`); a freshly planned task must
    // surface in its day's window and nowhere adjacent.
    let inWindow = try await service.getScheduledTasks(
      from: "2026-04-15", to: "2026-04-15", limit: 50)
    #expect(inWindow.contains { $0.id == created.id })
    let dayAfter = try await service.getScheduledTasks(
      from: "2026-04-16", to: "2026-04-16", limit: 50)
    #expect(!dayAfter.contains { $0.id == created.id })
  }

  @Test("text filter matches notes, not just the title")
  func textFilterMatchesNotes() async throws {
    let service = try makeService()
    let marker = "contract-notes-\(UUID().uuidString.prefix(8))"
    let created = try await service.createTask(
      title: "Unrelated title", notes: "the marker lives here: \(marker)")

    let listed = try await tasks(service, status: "all", marker: marker)
    #expect(listed.map(\.id) == [created.id])
  }

  @Test(
    "daily reviews round-trip and history lists newest-first within limit")
  func reviewHistoryContract() async throws {
    let service = try makeService()
    // The store enforces the review write window (today-7 … today+1), so the
    // contract writes within it: the three days before today.
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    func day(_ offset: Int) -> String {
      formatter.string(from: Date(timeIntervalSinceNow: TimeInterval(offset) * 86_400))
    }
    for (date, summary) in [(day(-3), "oldest"), (day(-1), "newest"), (day(-2), "middle")] {
      _ = try await service.upsertDailyReviewPreservingLinks(
        date: date, summary: summary, mood: 3, energyLevel: 3,
        wins: nil, blockers: nil, learnings: nil)
    }

    let loaded = try #require(try await service.loadDailyReview(date: day(-2)))
    #expect(loaded.summary == "middle")

    // History is newest-first and honors the limit — the contract the
    // Recent Reviews strip depends on.
    let history = try await service.getReviewHistory(
      from: day(-3), to: day(-1), limit: 2)
    #expect(history.map(\.date) == [day(-1), day(-2)])

    // Backdates beyond the window are rejected, not silently absorbed.
    await #expect(throws: (any Error).self) {
      _ = try await service.upsertDailyReviewPreservingLinks(
        date: day(-30), summary: "stale", mood: nil, energyLevel: nil,
        wins: nil, blockers: nil, learnings: nil)
    }
  }

  @Test(
    "listTasks honors the canonical sort: priority_effective ASC, then id")
  func canonicalSort() async throws {
    let service = try makeService()
    let marker = "contract-sort-\(UUID().uuidString.prefix(8))"

    // Created in scrambled priority order; the canonical key must put P1
    // first regardless of insertion order.
    var byPriority: [LorvexTask.Priority: LorvexTask.ID] = [:]
    for priority in [LorvexTask.Priority.p2, .p3, .p1] {
      let created = try await service.createTask(
        title: "\(priority.rawValue) \(marker)", notes: "")
      _ = try await service.updateTask(
        id: created.id, title: created.title, notes: "",
        priority: priority, estimatedMinutes: nil, plannedDate: nil, tags: [], dependsOn: [])
      byPriority[priority] = created.id
    }

    let listed = try await tasks(service, status: "all", marker: marker)
    let ids = listed.map(\.id)
    #expect(ids.count == 3)
    #expect(ids.first == byPriority[.p1])
    #expect(ids.last == byPriority[.p3])
  }
}
