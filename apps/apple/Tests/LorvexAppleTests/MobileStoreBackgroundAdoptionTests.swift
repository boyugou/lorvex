import Foundation
import Synchronization
import Testing

@testable import LorvexCore
@testable import LorvexMobile

/// The store is closed while the iPhone app is in the background. These pin
/// what a refresh does then, and how a write made there is still adopted.

@MainActor
@Test("a refresh while the store is closed keeps what is loaded and raises no error")
func aRefreshWhileTheStoreIsClosedChangesNothing() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let loaded = store.snapshot.today.tasks.map(\.id)
  #expect(!loaded.isEmpty)

  let result = await DatabaseSuspension.$suspendedOverride.withValue(true) {
    await store.refresh()
  }

  #expect(result == .noData)
  #expect(store.snapshot.today.tasks.map(\.id) == loaded)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test("a write made in the background is adopted with the store taken back for the refresh")
func aBackgroundWriteIsAdoptedInsideTheStoreBracket() async throws {
  let core = try makeInMemoryCore()
  let scheduler = RecordingTaskReminderScheduler()
  let store = MobileStore(core: core, taskReminderScheduler: scheduler)
  let task = try await core.createTask(title: "Call the venue", notes: "")
  let iso = ISO8601DateFormatter()
  iso.formatOptions = [.withInternetDateTime]
  let fire = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3600).rounded())
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: [iso.string(from: fire)])
  await store.refresh()
  #expect(await scheduler.lastScheduledIDs() == [task.id])

  // The bracket the iOS app installs: the store is open only between the two.
  let events = Mutex<[String]>([])
  let access = DatabaseSuspension.BackgroundAccess(
    begin: { events.withLock { $0.append("begin") } },
    end: { events.withLock { $0.append("end") } })

  // The reminder's Complete button, handled while the app is in the background.
  _ = try await core.completeTask(id: task.id)
  await DatabaseSuspension.$backgroundAccessOverride.withValue(access) {
    _ = await store.refreshAdoptingBackgroundWrite()
  }

  #expect(events.withLock { $0 } == ["begin", "end"])
  // The refresh ran: the finished task's reminder is no longer armed.
  #expect(await scheduler.lastScheduledIDs().isEmpty)
}

/// Leaving the iPhone app closes the store at once, which would fail every
/// record a running import has yet to write, so the import holds the store
/// (and the background time that comes with it) from its first step to its
/// last.
@MainActor
@Test
func mobileStoreDataImportHoldsTheStoreForItsWholeLength() async throws {
  let store = MobileStore(core: try makeInMemoryCore(), todayString: { "2026-05-23" })
  let events = Mutex<[String]>([])
  let access = DatabaseSuspension.BackgroundAccess(
    begin: { events.withLock { $0.append("begin") } },
    end: { events.withLock { $0.append("end") } })

  _ = try await DatabaseSuspension.$backgroundAccessOverride.withValue(access) {
    try await store.applyDataImport(
      plan: LorvexImportPlan(entries: []),
      decoded: LorvexDataImporter.DecodedImport(payload: LorvexDataExportPayload()))
  }

  #expect(events.withLock { $0 } == ["begin", "end"])
  #expect(!store.isDataImportRunning)
}

/// A silent push that reaches a locked iPhone runs the sync pass and then
/// adopts what it applied, which is what re-plans the reminders, the badge, and
/// the widgets; and the wake that re-arms reminders also publishes the day's
/// widget snapshot. A background launch builds no root view, so the app starts
/// the store's observers itself.
@Test
func backgroundWakesAdoptWhatTheyApplied() throws {
  func source(_ path: String) throws -> String {
    try String(contentsOf: mobilePackageRoot().appending(path: path), encoding: .utf8)
  }
  let sync = try source("Sources/LorvexMobile/MobileStoreCloudSyncActions.swift")
  let push = try #require(sync.range(of: "public func handleCloudKitPush("))
  let pushBody = sync[push.upperBound...].prefix(900)
  let pass = try #require(pushBody.range(of: "let result = await self.runCloudSyncCycle()"))
  let adopt = try #require(
    pushBody.range(of: "await self.reloadInboundSurfacesIfNeeded(after: result)"))
  #expect(pass.lowerBound < adopt.lowerBound)

  let app = try source("Sources/LorvexMobileApp/LorvexMobileApp.swift")
  let replenish = try #require(app.range(of: "await store.replenishReminderWindow()"))
  let widget = try #require(app.range(of: "await store.publishWidgetSnapshotInBackgroundWake()"))
  #expect(replenish.lowerBound < widget.lowerBound)
  let launch = try #require(app.range(of: "LorvexMobileAppDelegate.launchStore = builtStore"))
  let observers = try #require(app.range(of: "builtStore.startLifetimeObserversIfNeeded()"))
  #expect(launch.lowerBound < observers.lowerBound)
}

private func mobilePackageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
