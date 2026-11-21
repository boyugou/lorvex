import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@Test func taskRowPlanKeepsWorkAndDeadlineIndependentAcrossTimeZones() throws {
  // Los Angeles is still on Saturday as Tokyo moves into the DST Sunday.
  let now = try #require(ISO8601DateFormatter().date(from: "2026-03-08T03:00:00Z"))
  let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let work = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-03-08"))
  let due = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-03-11"))
  var task = LorvexTask(id: "row", title: "Write the brief", notes: "", priority: .p2,
    status: .open, dueDate: due, plannedDate: work, estimatedMinutes: nil, tags: [])
  let plan = try #require(LorvexTaskRowPlan(task, now: now, timeZone: pacific))
  #expect(plan.work.contains(LorvexDayPhrase.phrase(for: work, logicalDay: "2026-03-07", position: .inline)))
  #expect(plan.deadline == LorvexTaskRowPlan.dueLabel(
    LorvexDayPhrase.phrase(for: due, logicalDay: "2026-03-07", position: .inline)))
  #expect(LorvexTaskRowPlan(task, now: now, timeZone: tokyo)?.work != plan.work)
  #expect(LorvexTaskRowPlan(task, now: now, timeZone: tokyo, dayInHeading: "2026-03-08") == nil)
  task.dueDate = work
  task.plannedTime = 600..<645
  let same = try #require(LorvexTaskRowPlan(task, now: now, timeZone: tokyo))
  #expect(same.sharesDeadline && same.deadline == nil && same.dueSoon)
  #expect(same.work.contains(lorvexClockRangeLabel(startMinutes: 600, endMinutes: 645)))
  #expect(same.workOnly != same.work)
  #expect(LorvexTaskRowPlan(task, now: now, timeZone: tokyo, dayInHeading: "2026-03-08",
    timeAlreadyShown: true) == nil)
  task.dueDate = nil
  task.plannedTime = nil
  let past = try #require(LorvexTaskRowPlan(task, now: due, timeZone: tokyo))
  #expect(!past.overdue && !past.dueSoon && past.deadline == nil)
  #expect(taskAccessibilityLabel(task, timeZone: tokyo).contains(
    try #require(LorvexTaskRowPlan(task, timeZone: tokyo)).work))
  task.plannedDate = nil
  task.dueDate = due
  #expect(LorvexTaskRowPlan(task, now: now, timeZone: tokyo) == nil)
}

@MainActor
@Test func mobileSmartCollectionFiltersBeforeCountingPagingAndSearching() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let store = MobileStore(core: core)
  let list = try await core.createList(name: "Travel", description: nil, color: nil, icon: nil)
  let date = try #require(LorvexDateFormatters.ymdUTC.date(from: "2027-01-05"))
  _ = try await core.batchCreateTasks((0..<210).map { index in
    TaskCreateDraft(title: "Passport 护照 \(index)", priority: .p1)
  })
  let planned = try await core.createTask(.init(title: "Passport 护照 plan", listID: list.id,
    priority: .p3, plannedDate: date))
  let due = try await core.createTask(.init(title: "Passport 护照 due", priority: .p3, dueDate: date))
  let both = try await core.createTask(.init(title: "Passport 护照 both", priority: .p3,
    dueDate: date, plannedDate: date))
  _ = try await core.startTask(id: planned.id)
  _ = try await core.createTask(.init(title: "Passport 护照 hidden", availableFrom: date))
  let done = try await core.createTask(.init(title: "Passport 护照 closed", plannedDate: date))
  _ = try await core.completeTask(id: done.id)

  for query in ["", "Passport", "护照"] {
    let first = await store.taskWorkspacePage(scope: .scheduled, query: query, limit: 1)
    #expect(first.totalMatching == 3)
    #expect(first.tasks.count == 1)
    let next = try #require(first.nextOffset)
    let rest = await store.taskWorkspacePage(scope: .scheduled, query: query, limit: 2, offset: next)
    let combined = first.appending(rest)
    #expect(combined.totalMatching == 3 && combined.nextOffset == nil)
    #expect(Set(combined.tasks.map(\.id)) == [planned.id, due.id, both.id])
  }
  let priority = await store.taskWorkspacePage(scope: .priority, query: "Passport", limit: 1)
  #expect(priority.totalMatching == 210 && priority.tasks.count == 1)
  let listPage = await store.taskWorkspacePage(scope: .list(list.id), query: "Passport", limit: 1)
  #expect(listPage.totalMatching == 1 && listPage.tasks.map(\.id) == [planned.id])
}
