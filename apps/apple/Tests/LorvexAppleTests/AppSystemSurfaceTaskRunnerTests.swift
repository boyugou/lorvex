import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func taskIntentRunnerHandlesTaskReadWriteAndLifecycleActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let createdTitle = try await LorvexTaskIntentRunner.captureTask(
    title: "  Shortcut captured task  ",
    notes: "Created from App Intents.",
    core: core
  )
  var today = try await core.loadToday()
  let created = try #require(today.tasks.first { $0.title == "Shortcut captured task" })
  #expect(createdTitle == "Shortcut captured task")
  #expect(created.notes == "Created from App Intents.")

  // Plan the task a few days out relative to today so it always lands inside
  // the 10-day "upcoming" window the assertion below checks — a hardcoded date
  // silently broke the day the clock reached it.
  let plannedDate = LorvexDateFormatters.ymd.string(
    from: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date())
  let detailUpdated = try await LorvexTaskIntentRunner.updateTask(
    id: " \(created.id) ",
    title: "  Shortcut updated task  ",
    notes: "  Updated from Shortcuts  ",
    priority: 1,
    estimatedMinutes: 45,
    plannedDate: " \(plannedDate) ",
    tagsText: " shortcut, apple ",
    dependsOnText: nil,
    core: core
  )
  #expect(detailUpdated.id == created.id)
  #expect(detailUpdated.title == "Shortcut updated task")
  #expect(detailUpdated.notes == "Updated from Shortcuts")
  #expect(detailUpdated.priority == .p1)
  #expect(detailUpdated.estimatedMinutes == 45)
  // Tags added in one write surface alphabetically (shared created_at).
  #expect(detailUpdated.tags == ["apple", "shortcut"])

  let readTask = try await LorvexTaskIntentRunner.readTask(id: " \(created.id) ", core: core)
  #expect(readTask.title == "Shortcut updated task")
  let searchResults = try await LorvexTaskIntentRunner.searchTasks(
    query: "shortcut",
    status: "open",
    limit: 10,
    core: core
  )
  #expect(searchResults.query == "shortcut")
  #expect(searchResults.tasks.map(\.id).contains(created.id))
  let listedTasks = try await LorvexTaskIntentRunner.listTasks(
    status: "open",
    listID: nil,
    priority: 1,
    text: "shortcut",
    limit: 10,
    core: core
  )
  #expect(listedTasks.tasks.map(\.id).contains(created.id))
  let upcomingTasks = try await LorvexTaskIntentRunner.readUpcomingTasks(
    daysAhead: 10,
    limit: 10,
    core: core
  )
  #expect(upcomingTasks.map(\.id).contains(created.id))

  let deferredTask = try await core.createTask(title: "Shortcut deferred task", notes: "")
  let deferDay = try await core.getSessionContext().date
  let expectedDeferredDay = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(deferDay, days: 1))
  _ = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(
    id: deferredTask.id,
    core: core
  )
  let deferredTasks = try await LorvexTaskIntentRunner.readDeferredTasks(limit: 10, core: core)
  #expect(deferredTasks.tasks.map(\.id).contains(deferredTask.id))
  let surfacedDeferred = try #require(deferredTasks.tasks.first { $0.id == deferredTask.id })
  // Deferral pushes planned_date forward and leaves the task open.
  #expect(surfacedDeferred.status == .open)
  #expect(
    surfacedDeferred.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:))
      == expectedDeferredDay)
  // A deferred task is open, so it surfaces under the open status filter (there
  // is no `deferred` status).
  let searchedDeferredTasks = try await LorvexTaskIntentRunner.searchTasks(
    query: "deferred",
    status: "open",
    limit: 10,
    core: core
  )
  #expect(searchedDeferredTasks.tasks.map(\.id).contains(deferredTask.id))
  let listedDeferredTasks = try await LorvexTaskIntentRunner.listTasks(
    status: "open",
    priority: 2,
    text: "deferred",
    limit: 10,
    core: core
  )
  #expect(listedDeferredTasks.tasks.map(\.id).contains(deferredTask.id))

  let blocker = try await core.createTask(title: "Shortcut dependency blocker", notes: "")
  _ = try await LorvexTaskIntentRunner.updateTask(
    id: created.id,
    title: nil,
    notes: nil,
    priority: nil,
    estimatedMinutes: nil,
    plannedDate: nil,
    tagsText: nil,
    dependsOnText: blocker.id,
    core: core
  )
  let graph = try await LorvexTaskIntentRunner.readDependencyGraph(
    rootTaskID: " \(created.id) ",
    includeInactive: false,
    core: core
  )
  #expect(graph.nodes.map(\.id).contains(created.id))
  #expect(graph.edges.contains { $0.from == created.id && $0.to == blocker.id })

  let lifecycleTask = try await core.createTask(title: "Shortcut lifecycle task", notes: "")
  let cancelledTitle = try await LorvexTaskIntentRunner.cancelTask(
    id: " \(lifecycleTask.id) ",
    core: core
  )
  #expect(cancelledTitle == "Shortcut lifecycle task")
  today = try await core.loadToday()
  // Cancelled tasks leave the open-only Today snapshot.
  #expect(!today.tasks.contains { $0.id == lifecycleTask.id })
  #expect(try await core.loadTask(id: lifecycleTask.id).status == .cancelled)
  let reopenedTitle = try await LorvexTaskIntentRunner.reopenTask(
    id: " \(lifecycleTask.id) ",
    core: core
  )
  #expect(reopenedTitle == "Shortcut lifecycle task")
  today = try await core.loadToday()
  #expect(today.tasks.first { $0.id == lifecycleTask.id }?.status == .open)

  let completedTitle = try await LorvexTaskIntentRunner.completeTask(id: created.id, core: core)
  today = try await core.loadToday()
  #expect(completedTitle == "Shortcut updated task")
  // The completed task leaves the open-only Today snapshot.
  #expect(!today.tasks.contains { $0.id == created.id })
  #expect(try await core.loadTask(id: created.id).status == .completed)
}

@Test
func systemIntentDeferUntilTomorrowUsesConfiguredProductDayAcrossTimezones() async throws {
  // These zones are 25 hours apart, so their civil days can never both equal
  // one device-local fallback day. Compute the oracle independently from the
  // core/session-context path under test.
  for zoneID in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
    let timeZone = try #require(TimeZone(identifier: zoneID))
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"

    let core = try await makeSeededInMemoryCore()
    let task = try await core.createTask(title: "Defer in \(zoneID)", notes: "")
    _ = try await core.setPreference(key: "timezone", value: zoneID)

    let before = Date()
    _ = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(
      id: task.id, core: core)
    let after = Date()

    // Accept either side only if the call itself crossed this product zone's
    // midnight. The expected days still come solely from Foundation + the
    // configured zone, never from `getSessionContext()` or the intent runner.
    let expectedStorageDays = Set(
      [before, after].compactMap {
        LorvexDateFormatters.ymdUTCAddingDays(formatter.string(from: $0), days: 1)
      })

    let deferred = try #require(try await core.loadTask(id: task.id).plannedDate)
    #expect(expectedStorageDays.contains(LorvexDateFormatters.ymdUTC.string(from: deferred)))
  }
}

@Test
func taskIntentDeferUntilTomorrowDoesNotFallbackToNowInSource() throws {
  let source = try String(
    contentsOf: packageRoot()
      .appending(path: "Sources/LorvexCore/Services/SystemIntentTaskActions.swift"),
    encoding: .utf8
  )
  #expect(!source.contains("Calendar.current"))
  #expect(source.contains("core.getSessionContext().date"))
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
