import AppIntents
import Foundation
import LorvexCore
import Testing

@testable import LorvexSystemIntents

// The work behind the Siri reminder actions, run against a real in-memory
// core, and the actions' own declarations. Dates are given with a year, a
// month and a day, which name the same stored day in every zone.

private let siriActionZone = TimeZone(identifier: "America/Los_Angeles")!

private var siriActionCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = siriActionZone
  return calendar
}

private func siriStoredDay(_ key: String) -> Date {
  LorvexDateFormatters.ymdUTC.date(from: key)!
}

private func siriCreate(
  _ fields: SiriTaskFields, core: any LorvexCoreServicing
) async throws -> LorvexTask {
  try await LorvexSystemIntentRunner.createSiriTask(
    fields, timeZone: siriActionZone, core: core)
}

private func siriUpdate(
  _ id: LorvexTask.ID, _ fields: SiriTaskFields, core: any LorvexCoreServicing
) async throws -> LorvexTask {
  try await LorvexSystemIntentRunner.updateSiriTask(
    id: id, fields: fields, timeZone: siriActionZone, core: core)
}

/// The date `task` reports to Siri, as Siri would hand it back unchanged.
private func siriReportedDate(_ task: LorvexTask) -> DateComponents? {
  SiriTaskMapping.moment(for: task).map(SiriTaskMapping.dateComponents(for:))
}

// MARK: - Create

@Test
func siriCreateWritesEveryGivenField() async throws {
  let core = try makeInMemoryCore()
  let list = try await core.createList(name: "Errands", description: nil)
  let task = try await siriCreate(
    SiriTaskFields(
      title: "  Buy milk ",
      note: "Two percent",
      tags: ["home", "errand"],
      urls: [URL(string: "https://example.com/milk")!],
      date: DateComponents(year: 2026, month: 12, day: 4, hour: 15, minute: 30),
      isFlagged: true,
      listID: list.id),
    core: core)

  #expect(task.title == "Buy milk")
  #expect(task.notes == "Two percent\n\nhttps://example.com/milk")
  #expect(task.tags.sorted() == ["errand", "home"])
  #expect(task.priority == .p1)
  #expect(task.listID == list.id)
  #expect(task.plannedDate == siriStoredDay("2026-12-04"))
  #expect(task.plannedTime == (15 * 60 + 30)..<(16 * 60))
  // The reminder's date is the planned day; it sets no deadline.
  #expect(task.dueDate == nil)
  #expect(task.recurrence == nil)
}

@Test
func siriCreateWithOnlyATitleIsAnUndatedP2Task() async throws {
  let core = try makeInMemoryCore()
  let task = try await siriCreate(SiriTaskFields(title: "Call the bank", isFlagged: false), core: core)
  #expect(task.priority == .p2)
  #expect(task.plannedDate == nil)
  #expect(task.plannedTime == nil)
  #expect(task.notes.isEmpty)
  #expect(task.tags.isEmpty)
}

@Test
func siriCreateRepeatingTaskIsDueOnTheFirstDayTheRuleLandsOn() async throws {
  let core = try makeInMemoryCore()
  let calendar = siriActionCalendar

  // 4 December 2026 is a Friday; the rule lands on Mondays.
  let dated = try await siriCreate(
    SiriTaskFields(
      title: "Take out the bins",
      date: DateComponents(year: 2026, month: 12, day: 4),
      recurrence: .weekly(calendar: calendar, weekdays: [.every(.monday)])),
    core: core)
  #expect(dated.recurrence?.freq == .weekly)
  #expect(dated.recurrence?.byDay == ["MO"])
  #expect(dated.plannedDate == siriStoredDay("2026-12-04"))
  #expect(dated.dueDate == siriStoredDay("2026-12-07"))

  // Without a date the first occurrence counts from the logical today.
  let undated = try await siriCreate(
    SiriTaskFields(
      title: "Water the plants",
      recurrence: .weekly(calendar: calendar, weekdays: [.every(.monday)])),
    core: core)
  let today = siriStoredDay(try await core.getSessionContext().date)
  let due = try #require(undated.dueDate)
  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = .gmt
  #expect(utc.component(.weekday, from: due) == 2)
  #expect(due >= today)
  #expect(due < today.addingTimeInterval(7 * 86_400))
  #expect(undated.plannedDate == nil)
}

@Test
func siriCreateRefusesWhatATaskCannotHoldBeforeWriting() async throws {
  let core = try makeInMemoryCore()
  await #expect(throws: LorvexCoreError.self) {
    _ = try await siriCreate(SiriTaskFields(title: "   "), core: core)
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await siriCreate(
      SiriTaskFields(
        title: "Stretch", recurrence: .hourly(calendar: siriActionCalendar)),
      core: core)
  }
  let all = try await core.listTasks(
    status: "all", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  #expect(all.tasks.isEmpty)
}

@Test
func siriRepeatEveryOtherWeekLandsOnTheDaysSiriMeant() async throws {
  // 4 November 2035 is a Sunday. Every other week on Sunday and Monday, in
  // weeks that start on Sunday, lands on the 4th and the 5th; in weeks that
  // start on Monday the Monday after the 4th is in the week left out, and the
  // next one is the 12th.
  for (firstWeekday, weekStart, nextDue) in [(1, "SU", "2035-11-05"), (2, nil, "2035-11-12")] {
    let core = try makeInMemoryCore()
    var calendar = siriActionCalendar
    calendar.firstWeekday = firstWeekday
    let created = try await siriCreate(
      SiriTaskFields(
        title: "Put the bins out",
        date: DateComponents(year: 2035, month: 11, day: 4),
        recurrence: .weekly(
          calendar: calendar, interval: 2, weekdays: [.every(.sunday), .every(.monday)])),
      core: core)
    #expect(created.recurrence?.wkst == weekStart)
    #expect(created.dueDate == siriStoredDay("2035-11-04"))

    _ = try await core.completeTaskReturningTask(id: created.id)
    let open = try await core.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
    let next = try #require(open.tasks.first { $0.title == "Put the bins out" })
    #expect(next.dueDate == siriStoredDay(nextDue), "weeks starting on \(firstWeekday)")
  }
}

// MARK: - Update

@Test
func siriUpdateWritesOnlyTheGivenFields() async throws {
  let core = try makeInMemoryCore()
  let list = try await core.createList(name: "Work", description: nil)
  let created = try await core.createTask(
    TaskCreateDraft(
      title: "Draft report", notes: "Outline first", priority: .p3, estimatedMinutes: 45,
      dueDate: siriStoredDay("2026-12-10"), tags: ["q4"]))

  let updated = try await siriUpdate(
    created.id,
    SiriTaskFields(
      title: "Draft the report",
      tags: ["q4", "writing"],
      urls: [URL(string: "https://example.com/brief")!],
      listID: list.id),
    core: core)

  #expect(updated.title == "Draft the report")
  #expect(updated.tags.sorted() == ["q4", "writing"])
  #expect(updated.notes == "Outline first\n\nhttps://example.com/brief")
  #expect(updated.listID == list.id)
  // Fields the request did not give stay as stored.
  #expect(updated.priority == .p3)
  #expect(updated.estimatedMinutes == 45)
  #expect(updated.dueDate == siriStoredDay("2026-12-10"))
  #expect(updated.plannedDate == nil)
}

@Test
func siriUpdateDateSetsThePlannedDayAndTime() async throws {
  let core = try makeInMemoryCore()
  let created = try await core.createTask(
    TaskCreateDraft(
      title: "Review", estimatedMinutes: 45, plannedDate: siriStoredDay("2026-12-04"),
      plannedTime: 540..<600))

  // A new clock time on the same day keeps the time's length.
  let retimed = try await siriUpdate(
    created.id,
    SiriTaskFields(date: DateComponents(year: 2026, month: 12, day: 4, hour: 14)),
    core: core)
  #expect(retimed.plannedDate == siriStoredDay("2026-12-04"))
  #expect(retimed.plannedTime == 840..<900)

  // The same day without a time leaves the time alone.
  let sameDay = try await siriUpdate(
    created.id, SiriTaskFields(date: DateComponents(year: 2026, month: 12, day: 4)), core: core)
  #expect(sameDay.plannedTime == 840..<900)

  // Another day with the same clock time moves the task and keeps its time.
  let moved = try await siriUpdate(
    created.id,
    SiriTaskFields(date: DateComponents(year: 2026, month: 12, day: 7, hour: 14)),
    core: core)
  #expect(moved.plannedDate == siriStoredDay("2026-12-07"))
  #expect(moved.plannedTime == 840..<900)

  // Another day without a time clears the time, as every planned-day move does.
  let dayOnly = try await siriUpdate(
    created.id, SiriTaskFields(date: DateComponents(year: 2026, month: 12, day: 9)), core: core)
  #expect(dayOnly.plannedDate == siriStoredDay("2026-12-09"))
  #expect(dayOnly.plannedTime == nil)

  // A clock time on a task without one uses the estimate as its length.
  let timedAgain = try await siriUpdate(
    created.id,
    SiriTaskFields(date: DateComponents(year: 2026, month: 12, day: 9, hour: 8)),
    core: core)
  #expect(timedAgain.plannedTime == 480..<525)
}

@Test
func siriUpdateRestatingReportedValuesChangesNothing() async throws {
  let core = try makeInMemoryCore()

  // A task with only a deadline reports the deadline as its date. Handing
  // that date back must not give the task a planned day.
  let deadlineOnly = try await core.createTask(
    TaskCreateDraft(
      title: "File taxes", notes: "Forms in the drawer", priority: .p3,
      dueDate: siriStoredDay("2026-12-15"), tags: ["money"]))
  let restated = try await siriUpdate(
    deadlineOnly.id,
    SiriTaskFields(
      title: deadlineOnly.title,
      note: deadlineOnly.notes,
      tags: Set(deadlineOnly.tags),
      date: siriReportedDate(deadlineOnly),
      isCompleted: false,
      isFlagged: false),
    core: core)
  #expect(restated == deadlineOnly)

  // A task that repeats from its completion day reports a plain repeat.
  // Handing that rule back must not change what the repeat counts from.
  let created = try await core.createTask(
    TaskCreateDraft(title: "Change the filter", dueDate: siriStoredDay("2026-12-15")))
  let repeating = try await core.setTaskRecurrence(
    taskID: created.id,
    rule: TaskRecurrenceRule(freq: .daily, interval: 90, anchor: .completion))
  let reported = try #require(repeating.recurrence.flatMap { SiriTaskMapping.recurrence(for: $0) })
  let echoed = try await siriUpdate(
    repeating.id, SiriTaskFields(recurrence: reported), core: core)
  #expect(echoed == repeating)
  #expect(echoed.recurrence?.anchor == .completion)
}

@Test
func siriUpdateKeepsTheBlankSpaceInNotes() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(
    TaskCreateDraft(title: "Run the script", notes: "    make release\n"))
  #expect(task.notes == "    make release\n")

  // Handing the note back as reported writes nothing.
  let restated = try await siriUpdate(task.id, SiriTaskFields(note: task.notes), core: core)
  #expect(restated == task)

  // A link is added after the note, which keeps its indent.
  let linked = try await siriUpdate(
    task.id, SiriTaskFields(urls: [URL(string: "https://example.com/run")!]), core: core)
  #expect(linked.notes == "    make release\n\nhttps://example.com/run")
}

@Test
func siriUpdateFlagMapsToPriorityOne() async throws {
  let core = try makeInMemoryCore()
  let low = try await core.createTask(TaskCreateDraft(title: "Low", priority: .p3))
  let high = try await core.createTask(TaskCreateDraft(title: "High", priority: .p1))

  #expect(try await siriUpdate(low.id, SiriTaskFields(isFlagged: false), core: core).priority == .p3)
  #expect(try await siriUpdate(low.id, SiriTaskFields(isFlagged: true), core: core).priority == .p1)
  #expect(try await siriUpdate(high.id, SiriTaskFields(isFlagged: true), core: core).priority == .p1)
  #expect(try await siriUpdate(high.id, SiriTaskFields(isFlagged: false), core: core).priority == .p2)
}

@Test
func siriUpdateCompletesAndReopens() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(TaskCreateDraft(title: "Send the invoice"))

  let completed = try await siriUpdate(
    task.id, SiriTaskFields(title: "Send the final invoice", isCompleted: true), core: core)
  #expect(completed.status == .completed)
  #expect(completed.title == "Send the final invoice")

  let reopened = try await siriUpdate(task.id, SiriTaskFields(isCompleted: false), core: core)
  #expect(reopened.status == .open)
}

@Test
func siriUpdateRepeatRuleGivesAnUndatedTaskItsFirstDueDay() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(
    TaskCreateDraft(title: "Team sync", plannedDate: siriStoredDay("2026-12-04")))

  let updated = try await siriUpdate(
    task.id,
    SiriTaskFields(
      recurrence: .weekly(calendar: siriActionCalendar, weekdays: [.every(.monday)])),
    core: core)
  #expect(updated.recurrence?.freq == .weekly)
  #expect(updated.recurrence?.byDay == ["MO"])
  // 4 December 2026 is a Friday; the first Monday after it is the 7th.
  #expect(updated.dueDate == siriStoredDay("2026-12-07"))
  #expect(updated.plannedDate == siriStoredDay("2026-12-04"))

  // A different rule replaces the stored one and keeps the due day it has.
  let monthly = try await siriUpdate(
    task.id,
    SiriTaskFields(recurrence: .monthly(calendar: siriActionCalendar, daysOfTheMonth: [7])),
    core: core)
  #expect(monthly.recurrence?.freq == .monthly)
  #expect(monthly.dueDate == siriStoredDay("2026-12-07"))
}

@Test
func siriUpdateRefusesWhatATaskCannotHoldBeforeWriting() async throws {
  let core = try makeInMemoryCore()
  let task = try await core.createTask(TaskCreateDraft(title: "Stretch"))

  await #expect(throws: LorvexCoreError.self) {
    _ = try await siriUpdate(
      task.id,
      SiriTaskFields(
        title: "Stretch every hour", recurrence: .hourly(calendar: siriActionCalendar),
        isCompleted: true),
      core: core)
  }
  await #expect(throws: LorvexCoreError.self) {
    _ = try await siriUpdate(task.id, SiriTaskFields(title: "  "), core: core)
  }
  #expect(try await core.loadTask(id: task.id) == task)
}

// MARK: - Delete

@Test
func siriDeleteCancelsAndStopsARepeat() async throws {
  let core = try makeInMemoryCore()
  let single = try await core.createTask(TaskCreateDraft(title: "Old errand"))
  let repeating = try await core.createTask(
    TaskCreateDraft(
      title: "Weekly errand", dueDate: siriStoredDay("2026-12-07"),
      recurrence: TaskRecurrenceRule(freq: .weekly)))

  let result = try await LorvexSystemIntentRunner.cancelSiriTasks(
    ids: [single.id, repeating.id], core: core)
  #expect(Set(result.cancelled.map(\.id)) == [single.id, repeating.id])
  #expect(result.skipped.isEmpty)

  // The tasks are still in the store, cancelled, and nothing came back as a
  // next occurrence.
  #expect(try await core.loadTask(id: single.id).status == .cancelled)
  let stopped = try await core.loadTask(id: repeating.id)
  #expect(stopped.status == .cancelled)
  #expect(stopped.recurrence == nil)
  let all = try await core.listTasks(
    status: "all", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  #expect(all.tasks.count == 2)

  // A task that is already cancelled is skipped, and a cancelled task reopens.
  let again = try await LorvexSystemIntentRunner.cancelSiriTasks(ids: [single.id], core: core)
  #expect(again.cancelled.isEmpty)
  #expect(again.skipped == [single.id])
  #expect(try await core.reopenTaskReturningTask(id: single.id).status == .open)

  await #expect(throws: LorvexCoreError.self) {
    _ = try await LorvexSystemIntentRunner.cancelSiriTasks(ids: [], core: core)
  }
}

@Test
func siriDeleteOfACompletedTaskFailsAndLeavesItCompleted() async throws {
  let core = try makeInMemoryCore()
  let open = try await core.createTask(TaskCreateDraft(title: "Still to do"))
  let done = try await core.createTask(TaskCreateDraft(title: "Already done"))
  _ = try await core.completeTaskReturningTask(id: done.id)

  // The request fails with the reason the app has its own wording for.
  do {
    _ = try await LorvexSystemIntentRunner.cancelSiriTasks(ids: [open.id, done.id], core: core)
    Issue.record("cancelling a completed task did not fail")
  } catch {
    #expect(UserFacingError.classify(error).reason == .cancelingDoneTask)
  }
  // The task that could be cancelled is cancelled; the completed one is not.
  #expect(try await core.loadTask(id: open.id).status == .cancelled)
  #expect(try await core.loadTask(id: done.id).status == .completed)

  // A task that is gone needs nothing.
  let gone = try await LorvexSystemIntentRunner.cancelSiriTasks(
    ids: ["01JZZZZZZZZZZZZZZZZZZZZZZZ"], core: core)
  #expect(gone.cancelled.isEmpty)
}

@Test
func siriDeleteLeavesATaskWhoseLaterOccurrenceIsCompleted() async throws {
  let core = try makeInMemoryCore()
  // A repeating task that is open again while the occurrence it generated is
  // completed: complete it, reopen it (which withdraws the next occurrence),
  // reopen that occurrence by hand, and complete it.
  let first = try await core.createTask(
    TaskCreateDraft(
      title: "Weekly errand", dueDate: siriStoredDay("2026-12-07"),
      recurrence: TaskRecurrenceRule(freq: .weekly)))
  _ = try await core.completeTaskReturningTask(id: first.id)
  let all = try await core.listTasks(
    status: "all", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
  let second = try #require(all.tasks.first { $0.id != first.id })
  _ = try await core.reopenTaskReturningTask(id: first.id)
  _ = try await core.reopenTaskReturningTask(id: second.id)
  _ = try await core.completeTaskReturningTask(id: second.id)

  // Ending the series would cancel the completed occurrence, so the delete
  // fails with that reason and changes neither task.
  do {
    _ = try await LorvexSystemIntentRunner.cancelSiriTasks(ids: [first.id], core: core)
    Issue.record("the delete did not fail")
  } catch {
    #expect(UserFacingError.classify(error).reason == .endingRepeatWithCompletedOccurrence)
  }
  #expect(try await core.loadTask(id: first.id).status == .open)
  #expect(try await core.loadTask(id: second.id).status == .completed)
}

// MARK: - Entities and actions (macOS 27 and iOS 27)

@Test
func siriTaskEntityReportsTheTaskInTheReminderShape() async throws {
  guard #available(macOS 27.0, iOS 27.0, *) else { return }
  let core = try makeInMemoryCore()
  let list = try await core.createList(name: "Errands", description: nil)
  let planned = try await core.createTask(
    TaskCreateDraft(
      title: "Pick up parcel", notes: "Locker 12", listID: list.id, priority: .p1,
      dueDate: siriStoredDay("2026-12-20"), plannedDate: siriStoredDay("2026-12-04"),
      plannedTime: 540..<570, tags: ["post"]))
  let inboxed = try await core.createTask(
    TaskCreateDraft(title: "Renew passport", dueDate: siriStoredDay("2026-12-20")))

  let entities = try await LorvexSiriTaskEntityQuery.entities(
    for: [planned.id, "missing", inboxed.id], core: core)
  #expect(entities.map(\.id) == [planned.id, inboxed.id])

  let first = try #require(entities.first)
  #expect(first.title == "Pick up parcel")
  #expect(first.note.map { String($0.characters) } == "Locker 12")
  #expect(first.tags == ["post"])
  #expect(first.urls.isEmpty)
  #expect(first.locationTrigger == nil)
  #expect(first.isFlagged == true)
  #expect(first.isCompleted == false)
  #expect(first.creationDate != nil)
  #expect(first.completionDate == nil)
  #expect(first.list.id == list.id)
  #expect(first.list.name == "Errands")
  #expect(first.list.type == .standard)
  // A planned task reports its planned day and time, not its deadline.
  #expect(first.dueDate?.year == 2026)
  #expect(first.dueDate?.month == 12)
  #expect(first.dueDate?.day == 4)
  #expect(first.dueDate?.hour == 9)
  #expect(first.dueDate?.minute == 0)

  // A task with no list of its own is in the Inbox, and with no planned day
  // it reports its deadline, without a time.
  let second = try #require(entities.last)
  #expect(second.list.id == LorvexListNaming.inboxID)
  #expect(second.isFlagged == false)
  #expect(second.dueDate?.day == 20)
  #expect(second.dueDate?.hour == nil)
  #expect(second.note == nil)
}

@Test
func siriEntityQueriesFindActiveTasksAndLists() async throws {
  guard #available(macOS 27.0, iOS 27.0, *) else { return }
  let core = try makeInMemoryCore()
  _ = try await core.createList(name: "Garden", description: nil)
  let open = try await core.createTask(TaskCreateDraft(title: "Prune the roses"))
  let done = try await core.createTask(TaskCreateDraft(title: "Prune the hedge"))
  _ = try await core.completeTaskReturningTask(id: done.id)

  let matching = try await LorvexSiriTaskEntityQuery.entities(matching: "prune", core: core)
  #expect(matching.map(\.id) == [open.id])
  let suggested = try await LorvexSiriTaskEntityQuery.entities(matching: "  ", core: core)
  #expect(suggested.map(\.id) == [open.id])

  let lists = try await LorvexSiriListEntityQuery.entities(matching: "gard", core: core)
  #expect(lists.map(\.name) == ["Garden"])
  let everyList = try await LorvexSiriListEntityQuery.entities(matching: "", core: core)
  #expect(everyList.contains { $0.id == LorvexListNaming.inboxID })
  #expect(everyList.contains { $0.name == "Garden" })
}

@Test
func siriCreateAndUpdateIntentsPerformAgainstTheStore() async throws {
  guard #available(macOS 27.0, iOS 27.0, *) else { return }
  try await withIsolatedAppIntentDatabase {
    let create = CreateLorvexSiriTaskIntent()
    create.title = "Book the dentist"
    create.note = AttributedString("Ask about Tuesday")
    create.tags = ["health"]
    create.urls = []
    create.images = []
    create.isFlagged = true
    create.dueDate = DateComponents(year: 2026, month: 12, day: 4)
    let created = try #require(try await create.perform().value)
    #expect(created.title == "Book the dentist")
    #expect(created.isFlagged == true)
    #expect(created.list.id == LorvexListNaming.inboxID)

    let createList = CreateLorvexSiriListIntent()
    createList.type = .standard
    createList.name = "Health"
    let list = try #require(try await createList.perform().value)
    #expect(list.name == "Health")

    let update = UpdateLorvexSiriTaskIntent()
    update.target = created
    update.title = "Book the dentist for Tuesday"
    update.list = list
    update.isCompleted = true
    let updated = try #require(try await update.perform().value)
    #expect(updated.title == "Book the dentist for Tuesday")
    #expect(updated.list.id == list.id)
    #expect(updated.isCompleted)

    let stored = try await LorvexCoreRuntimeFactory.makeForAppIntent().loadTask(id: created.id)
    #expect(stored.status == .completed)
    #expect(stored.notes == "Ask about Tuesday")
    #expect(stored.tags == ["health"])
    #expect(stored.plannedDate == siriStoredDay("2026-12-04"))
  }
}

@Test
func siriDeleteIntentAsksBeforeItCancels() async throws {
  guard #available(macOS 27.0, iOS 27.0, *) else { return }
  try await withIsolatedAppIntentDatabase {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let task = try await core.createTask(TaskCreateDraft(title: "Keep me"))
    let entity = try #require(
      try await LorvexSiriTaskEntityQuery.entities(for: [task.id], core: core).first)

    // No system context supplies confirmation in a unit test, so `perform()`
    // throws at the confirmation request, which only fires before the cancel.
    let delete = DeleteLorvexSiriTasksIntent()
    delete.entities = [entity]
    await #expect(throws: (any Error).self) {
      _ = try await delete.perform()
    }
    #expect(try await core.loadTask(id: task.id).status == .open)

    // Nothing to delete is nothing to confirm.
    let empty = DeleteLorvexSiriTasksIntent()
    empty.entities = []
    _ = try await empty.perform()
  }
}

@Test
func siriIntentsAreClassifiedAndHiddenFromShortcuts() {
  guard #available(macOS 27.0, iOS 27.0, *) else { return }
  func assistantOnly<Intent: AssistantSchemaIntent>(_ type: Intent.Type) -> Bool {
    type.isAssistantOnly
  }
  // Each action is one Shortcuts already offers under another name.
  #expect(assistantOnly(CreateLorvexSiriTaskIntent.self))
  #expect(assistantOnly(UpdateLorvexSiriTaskIntent.self))
  #expect(assistantOnly(DeleteLorvexSiriTasksIntent.self))
  #expect(assistantOnly(CreateLorvexSiriListIntent.self))

  // Creating a task only adds, so it runs on a locked device like capture.
  #expect(CreateLorvexSiriTaskIntent.authenticationPolicy == .alwaysAllowed)
  let authenticated: [any AppIntent.Type] = [
    UpdateLorvexSiriTaskIntent.self,
    DeleteLorvexSiriTasksIntent.self,
    CreateLorvexSiriListIntent.self,
  ]
  for type in authenticated {
    #expect(type.authenticationPolicy == .requiresAuthentication, "\(type)")
  }
  let all: [any AppIntent.Type] = authenticated + [CreateLorvexSiriTaskIntent.self]
  for type in all {
    #expect(type is any LorvexSecuredIntent.Type, "\(type)")
    #expect(type.supportedModes == .background, "\(type)")
  }
}
