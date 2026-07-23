import Foundation
import LorvexCore
import Testing
@testable import LorvexWatch

@Suite("LorvexWatchStore actions")
@MainActor
struct LorvexWatchStoreActionTests {
  @Test("completePrimaryTask clears primaryTask when focus is removed")
  func completePrimaryTaskClearsPrimaryTask() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Ship alpha")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    #expect(store.primaryTask != nil, "Precondition: store must have a primary task before completing")

    await store.completePrimaryTask()

    #expect(store.primaryTask == nil)
    #expect(store.error == nil)
  }

  @Test("cancelPrimaryTask marks task cancelled and clears primaryTask")
  func cancelPrimaryTaskClearsPrimaryTask() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Cancel from watch")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    let taskID = try #require(store.primaryTask?.id)

    await store.cancelPrimaryTask()
    // Cancelled tasks leave the open-only Today snapshot; the row is the
    // evidence.
    let today = try await service.loadToday()
    #expect(!today.tasks.contains { $0.id == taskID })
    #expect(try await service.loadTask(id: taskID).status == .cancelled)
    #expect(store.primaryTask == nil)
    #expect(store.error == nil)
  }

  @Test("deferPrimaryTaskToTomorrow clears primaryTask when focus is deferred")
  func deferPrimaryTaskClearsPrimaryTask() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Defer from watch")

    let store = LorvexWatchStore(
      core: service,
      logicalDayOverride: "2026-05-24"
    )
    await store.refresh()
    let taskID = try #require(store.primaryTask?.id)

    await store.deferPrimaryTaskToTomorrow()
    let today = try await service.loadToday()
    let deferred = try #require(today.tasks.first { $0.id == taskID })

    #expect(deferred.status == .open)
    // Storage frame (`ymdUTC`) — the watch now anchors the planned day at UTC
    // midnight like every other surface, rather than storing a raw local instant.
    #expect(deferred.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == "2026-05-25")
    #expect(store.primaryTask == nil)
    #expect(store.error == nil)
  }

  @Test("watch defer-to-tomorrow anchors the next product day")
  func deferToTomorrowUsesProductDayStorageFrame() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Defer parity")

    let store = LorvexWatchStore(
      core: service,
      logicalDayOverride: "2026-05-24"
    )
    await store.refresh()
    let taskID = try #require(store.primaryTask?.id)

    await store.deferPrimaryTaskToTomorrow()
    let deferred = try #require(
      try await service.loadToday().tasks.first { $0.id == taskID })

    let expectedDay = try #require(
      LorvexDateFormatters.ymdUTC.date(from: "2026-05-25"))
    #expect(deferred.plannedDate == expectedDay)
  }

  @Test("removePrimaryTaskFromFocus clears today's focus plan")
  func removePrimaryTaskFromFocusClearsFocusPlan() async throws {
    let service = try await makeSeededInMemoryCore()
    try await seedWatchFocus(in: service, date: "2026-05-24", title: "Remove from watch focus")

    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")
    await store.refresh()
    let taskID = try #require(store.primaryTask?.id)

    await store.removePrimaryTaskFromFocus()
    let today = try await service.loadToday()
    let task = try #require(today.tasks.first { $0.id == taskID })

    #expect(task.status == .open)
    #expect(store.primaryTask == nil)
    #expect(store.currentFocus == nil)
    #expect(try await service.loadCurrentFocus(date: "2026-05-24") == nil)
    #expect(store.error == nil)
  }

  @Test("completePrimaryTask is a no-op when primaryTask is nil")
  func completeWithoutTaskIsNoOp() async throws {
    let service = try await makeSeededInMemoryCore()
    let store = LorvexWatchStore(core: service, logicalDayOverride: "2026-05-24")

    await store.completePrimaryTask()

    #expect(store.error == nil)
    #expect(store.primaryTask == nil)
  }
}
