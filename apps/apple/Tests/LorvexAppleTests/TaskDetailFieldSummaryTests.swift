import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

/// The values of the macOS task detail's rows, read from the selected task's draft.

@MainActor
@Test
func taskDetailDueSummaryNamesItsOwnDayEvenOnThePlannedDay() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  var draft = TaskCreateDraft(title: "File the claim", notes: "")
  draft.plannedDate = try store.storageDate(daysFromLogicalToday: 0)
  draft.dueDate = try store.storageDate(daysFromLogicalToday: 0)
  let task = try await core.createTask(draft)
  await store.refresh()

  store.selectTaskFromList(task.id)

  #expect(store.taskDetailDoOnSummary == "Today")
  // The Due row stands alone, so a deadline on the planned day still names it.
  #expect(store.taskDetailDueSummary == "today")

  _ = try await core.updateTask(
    TaskUpdateDraft(id: task.id, dueDate: .set(try store.storageDate(daysFromLogicalToday: 1))))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(store.taskDetailDueSummary == "tomorrow")
}

/// The When row says when the plan would finish the task late, and stops
/// saying it once the planned day is back on the deadline.
@MainActor
@Test
func taskDetailDoOnSummarySaysWhenThePlanFallsAfterTheDeadline() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  var draft = TaskCreateDraft(title: "Book the venue", notes: "")
  draft.plannedDate = try store.storageDate(daysFromLogicalToday: 1)
  draft.dueDate = try store.storageDate(daysFromLogicalToday: 0)
  let task = try await core.createTask(draft)
  await store.refresh()

  store.selectTaskFromList(task.id)
  #expect(store.taskDetailPlannedIsAfterDeadline)
  #expect(store.taskDetailDoOnSummary == LorvexDayPhrase.afterDeadline("Tomorrow"))

  _ = try await core.updateTask(
    TaskUpdateDraft(id: task.id, plannedDate: .set(try store.storageDate(daysFromLogicalToday: 0))))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(!store.taskDetailPlannedIsAfterDeadline)
  #expect(store.taskDetailDoOnSummary == "Today")
}

@MainActor
@Test
func taskDetailHideUntilSummaryReadsAnArrivedDayAsUnset() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  var draft = TaskCreateDraft(title: "Renew the lease", notes: "")
  draft.availableFrom = try store.storageDate(daysFromLogicalToday: -3)
  let task = try await core.createTask(draft)
  await store.refresh()

  store.selectTaskFromList(task.id)
  #expect(store.taskDetailHideUntilSummary == nil)

  _ = try await core.updateTask(
    TaskUpdateDraft(id: task.id, availableFrom: .set(try store.storageDate(daysFromLogicalToday: 1))))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(store.taskDetailHideUntilSummary == "tomorrow")
}

@MainActor
@Test
func taskDetailWaitsOnRowNamesTheTaskItWaitsOn() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  // The seeded "Book the offsite venue" waits on "Draft the team offsite agenda".
  let agenda = try await core.loadTask(id: LorvexPreviewSeedID.agendaTask)
  store.selectTaskFromList(LorvexPreviewSeedID.venueTask)
  #expect(store.taskDetailWaitsOnTitle == agenda.title)

  // A task no loaded list holds is named once the detail reads its title.
  let elsewhere = try await core.createTask(TaskCreateDraft(title: "Confirm the caterer", notes: ""))
  store.taskDetailDependencies = [elsewhere.id]
  #expect(store.taskDetailWaitsOnTitle == nil)
  #expect(store.taskDetailDependencyCountSummary == "1 task")
  await store.refreshTaskDetailDependencyTitles()
  #expect(store.taskDetailWaitsOnTitle == "Confirm the caterer")

  // Several tasks read as a count.
  store.taskDetailDependencies = [agenda.id, elsewhere.id]
  await store.refreshTaskDetailDependencyTitles()
  #expect(store.taskDetailWaitsOnTitle == nil)
  #expect(store.taskDetailDependencyCountSummary == "2 tasks")
  store.taskDetailDependencies = []
  #expect(store.taskDetailDependencyCountSummary == nil)
}

/// The Reminder row names a lone reminder's day and time the way the When row
/// names a day and a time, in the product time zone, and counts several.
@Test
func reminderDayTimeNamesTheDayAndTheTimeInTheProductZone() throws {
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  // 00:30 UTC on October 4 is 9:30 that morning in Tokyo.
  let reminder = TaskReminder(id: "r", reminderAt: "2026-10-04T00:30:00Z", status: "pending")
  let instant = try #require(TaskReminderDateTime.instant(from: reminder.reminderAt))
  let time = TaskReminderDateTime.displayTimeString(from: instant, timeZone: tokyo)

  #expect(lorvexReminderDayTime(reminder, logicalDay: "2026-10-03", timeZone: tokyo) == "Tomorrow, \(time)")
  #expect(lorvexReminderDayTime(reminder, logicalDay: "2026-10-04", timeZone: tokyo) == "Today, \(time)")
  #expect(lorvexReminderDayTime(reminder, logicalDay: "2026-08-01", timeZone: tokyo) == "Oct 4, \(time)")
  #expect(
    lorvexReminderDayTime(
      TaskReminder(id: "x", reminderAt: "not a time", status: nil), logicalDay: "2026-10-03", timeZone: tokyo)
      == nil)
}

@MainActor
@Test
func taskDetailRemindersSummaryNamesOneReminderAndCountsSeveral() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let first = TaskReminder(id: "a", reminderAt: "2026-10-04T16:30:00Z", status: "pending")
  let second = TaskReminder(id: "b", reminderAt: "2026-10-05T16:30:00Z", status: "pending")
  func task(_ reminders: [TaskReminder]) -> LorvexTask {
    LorvexTask(
      id: "t", title: "Book the venue", notes: "", priority: .p2, status: .open, dueDate: nil,
      estimatedMinutes: nil, tags: [], reminders: reminders)
  }

  #expect(store.taskDetailRemindersSummary(task: task([])) == nil)
  #expect(
    store.taskDetailRemindersSummary(task: task([first]))
      == lorvexReminderDayTime(first, logicalDay: store.logicalTodayDateString, timeZone: store.logicalTimeZone))
  #expect(store.taskDetailRemindersSummary(task: task([first, second])) == "2 reminders")
}
