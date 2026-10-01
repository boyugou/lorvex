import Foundation
import LorvexCore
import Testing
@testable import LorvexWatch

@Suite("LorvexWatchStore actions")
@MainActor
struct LorvexWatchStoreActionTests {
  @Test("completing a task takes it off the watch list")
  func completeTaskTakesItOffTheList() async throws {
    let service = try makeInMemoryCore()
    let task = try await seedWatchTodayTask(in: service, date: "2026-05-24", title: "Ship alpha")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    #expect(store.tasks.map(\.id) == [task.id])

    await store.completeTask(id: task.id)

    #expect(store.tasks.isEmpty)
    #expect(try await service.loadTask(id: task.id).status == .completed)
    #expect(store.error == nil)
  }

  @Test("completing a listed task advances the day's edge ring")
  func completingTaskCountsTowardToday() async throws {
    let service = try makeInMemoryCore()
    let task = try await seedWatchTodayTask(in: service, date: "2026-05-24", title: "Ship alpha")
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    let before = store.completedTodayCount

    store.applyOptimisticUpdate(for: .cancelTask(id: "not-on-today"))
    #expect(store.completedTodayCount == before)
    store.applyOptimisticUpdate(for: .completeTask(id: task.id))
    #expect(store.completedTodayCount == before + 1)
    #expect(store.tasks.isEmpty)
  }

  @Test("cancelling a task marks it cancelled and takes it off the list")
  func cancelTaskTakesItOffTheList() async throws {
    let service = try makeInMemoryCore()
    let task = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Cancel from watch")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    await store.cancelTask(id: task.id)

    // Cancelled tasks leave the actionable-only Today snapshot; the row is the
    // evidence.
    let today = try await service.loadToday()
    #expect(!today.tasks.contains { $0.id == task.id })
    #expect(try await service.loadTask(id: task.id).status == .cancelled)
    #expect(store.tasks.isEmpty)
    #expect(store.error == nil)
  }

  @Test("deferring a task to tomorrow takes it off Today")
  func deferTaskTakesItOffToday() async throws {
    let service = try makeInMemoryCore()
    let day = try await service.getSessionContext().date
    let task = try await seedWatchTodayTask(in: service, date: day, title: "Defer from watch")

    let store = LorvexWatchStore(core: service)
    await store.refresh()
    #expect(store.tasks.map(\.id) == [task.id])

    await store.deferTaskToTomorrow(id: task.id)

    let deferred = try await service.loadTask(id: task.id)
    #expect(deferred.status == .open)
    #expect(
      deferred.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:))
        == LorvexDateFormatters.ymdUTCAddingDays(day, days: 1))
    #expect(store.tasks.isEmpty)
    #expect(store.error == nil)
  }

  @Test("watch defer-to-tomorrow anchors the next product day")
  func deferToTomorrowUsesProductDayStorageFrame() async throws {
    let service = try makeInMemoryCore()
    let task = try await seedWatchTodayTask(in: service, date: "2026-05-24", title: "Defer parity")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()

    await store.deferTaskToTomorrow(id: task.id)

    // Storage frame (`ymdUTC`): the planned day is anchored at UTC midnight
    // like every other surface, not stored as a raw local instant.
    let expectedDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2026-05-25"))
    #expect(try await service.loadTask(id: task.id).plannedDate == expectedDay)
  }

  @Test("starting a task moves it to the top; pausing returns it to Today's order")
  func startAndPauseReorderTheList() async throws {
    let service = try makeInMemoryCore()
    let first = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "First by priority", priority: .p1)
    let second = try await seedWatchTodayTask(
      in: service, date: "2026-05-24", title: "Second by priority", priority: .p3)

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    #expect(store.tasks.map(\.id) == [first.id, second.id])

    await store.startTask(id: second.id)
    #expect(store.tasks.map(\.id) == [second.id, first.id])
    #expect(store.tasks.first?.status == .inProgress)

    await store.pauseTask(id: second.id)
    #expect(store.tasks.map(\.id) == [first.id, second.id])
    #expect(store.tasks.allSatisfy { $0.status == .open })
    #expect(store.error == nil)
  }
}
