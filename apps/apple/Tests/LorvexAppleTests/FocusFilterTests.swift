import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

// MARK: - WidgetSnapshotProjector focus-filter tests

private func focusFilterSnapshot(filter: FocusFilterConfiguration) -> WidgetSnapshot {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    summary: "",
    tasks: [
      makeFocusFilterTask(id: "work-a", title: "Work A", listID: "work"),
      makeFocusFilterTask(id: "home-b", title: "Home B", listID: "home"),
      makeFocusFilterTask(id: "inbox-c", title: "Inbox C", listID: nil),
      makeFocusFilterTask(id: "work-d", title: "Work D", listID: "work"),
    ],
    briefing: "Work first, then home.",
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })
  return projector.snapshot(today: today, timezone: nil, focusFilter: filter)
}

@Test("an active Focus filter keeps only its lists' tasks, in Today's order")
func widgetSnapshotProjectorKeepsOnlyFilteredListsWhenFilterActive() {
  let snapshot = focusFilterSnapshot(filter: FocusFilterConfiguration(listIDs: ["work"]))

  #expect(snapshot.tasks.map(\.id) == ["work-a", "work-d"])
  #expect(snapshot.stats.todayCount == 2)
  #expect(snapshot.briefing == nil, "the briefing speaks about the whole day, hidden tasks included")
}

@Test("an inactive Focus filter keeps every task and the briefing")
func widgetSnapshotProjectorKeepsEverythingWhenFilterInactive() {
  let snapshot = focusFilterSnapshot(filter: .inactive)

  #expect(snapshot.tasks.map(\.id) == ["work-a", "home-b", "inbox-c", "work-d"])
  #expect(snapshot.briefing == "Work first, then home.")
}

@Test("a filter naming a list that no task is in leaves the glances empty, not whole")
func widgetSnapshotProjectorHonorsFilterWithNoMatches() {
  let snapshot = focusFilterSnapshot(filter: FocusFilterConfiguration(listIDs: ["deleted"]))

  #expect(snapshot.tasks.isEmpty)
  #expect(snapshot.stats.todayCount == 0)
}

// MARK: - FocusFilterStore round-trip tests

@Test
func focusFilterStoreRoundTrip() async throws {
  let root = focusFilterTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = FocusFilterStore(
    managedDatabasePath: root.appendingPathComponent("db.sqlite").path)

  let initial = try await store.load()
  #expect(initial == .inactive)

  let config = FocusFilterConfiguration(listIDs: ["work", "errands"])
  let saved = try await store.save(config)

  let loaded = try await store.load()
  #expect(loaded.listIDs == ["work", "errands"])
  #expect(loaded.isActive == true)
  #expect(saved.revision == 1)
}

@Test
func focusFilterStoreResetRestoresInactiveState() async throws {
  let root = focusFilterTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = FocusFilterStore(
    managedDatabasePath: root.appendingPathComponent("db.sqlite").path)

  _ = try await store.save(FocusFilterConfiguration(listIDs: ["work"]))
  let reset = try await store.reset()

  let loaded = try await store.load()
  #expect(loaded == .inactive)
  #expect(loaded.isActive == false)
  #expect(reset.revision == 2)
}

@Test
func focusFilterRevisionMintIsSerializedAcrossStoreInstances() async throws {
  let root = focusFilterTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let databasePath = root.appendingPathComponent("db.sqlite").path
  let first = FocusFilterStore(managedDatabasePath: databasePath)
  let second = FocusFilterStore(managedDatabasePath: databasePath)

  async let firstSave = first.save(FocusFilterConfiguration(listIDs: ["first"]))
  async let secondSave = second.save(FocusFilterConfiguration(listIDs: ["second"]))
  let (savedFirst, savedSecond) = try await (firstSave, secondSave)
  let revisions = [savedFirst.revision, savedSecond.revision].sorted()

  #expect(revisions == [1, 2])
  let final = try await first.loadState()
  #expect(final.revision == 2)
  #expect([["first"], ["second"]].contains(final.configuration.listIDs))
}

@Test
func factoryResetClearsCorruptFocusStateAndRejectsPreResetStoreWriter() async throws {
  let root = focusFilterTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let databaseURL = root.appendingPathComponent("db.sqlite")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  #expect(FileManager.default.createFile(atPath: databaseURL.path, contents: Data("db".utf8)))

  // This actor represents an intent request created before the reset. Its
  // generation token must not be able to revive an active policy afterward.
  let preResetStore = FocusFilterStore(managedDatabasePath: databaseURL.path)
  let sidecarURL = URL(
    fileURLWithPath: databaseURL.path + LorvexProductMetadata.focusFilterStateFileSuffix)
  try Data("corrupt private focus state".utf8).write(to: sidecarURL)

  let generation = try SwiftLorvexCoreService.resetManagedStorage(at: databaseURL)
  #expect(generation == 1)
  #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))

  let freshStore = FocusFilterStore(managedDatabasePath: databaseURL.path)
  let inactive = try await freshStore.loadState()
  #expect(inactive.configuration == .inactive)
  #expect(inactive.revision == 0)
  #expect(inactive.storageGeneration == 1)

  await #expect(throws: FocusFilterStoreError.supersededStorageGeneration) {
    _ = try await preResetStore.save(
      FocusFilterConfiguration(listIDs: ["stale-private-list"]))
  }
  #expect(try await freshStore.loadState() == inactive)
}

// MARK: - Helpers

private func makeFocusFilterTask(id: String, title: String, listID: String?) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    listID: listID
  )
}

private func focusFilterTempDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "lorvex-focus-filter-\(UUID().uuidString)", isDirectory: true)
}
