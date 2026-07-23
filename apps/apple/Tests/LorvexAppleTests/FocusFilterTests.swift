import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

// MARK: - WidgetSnapshotProjector focus-filter tests

@Test
func widgetSnapshotProjectorHidesNonFocusTasksWhenFilterActive() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makeFocusFilterTask(id: "focus-a", title: "Focus task A"),
      makeFocusFilterTask(id: "focus-b", title: "Focus task B"),
      makeFocusFilterTask(id: "extra-c", title: "Non-focus task C"),
    ],
    localChangeSequence: 1
  )
  let currentFocus = CurrentFocusPlan(
    date: "2026-05-22",
    taskIDs: ["focus-a", "focus-b"],
    briefing: "Focus time.",
    timezone: "UTC",
    localChangeSequence: 1
  )
  let filter = FocusFilterConfiguration(activeProfileID: "Lorvex Focus", showNonFocusTasks: false)
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })

  let snapshot = projector.snapshot(
    today: today,
    currentFocus: currentFocus,
    timezone: nil,
    focusFilter: filter
  )

  #expect(snapshot.focusTasks.map(\.id) == ["focus-a", "focus-b"])
  #expect(!snapshot.focusTasks.map(\.id).contains("extra-c"))
}

@Test
func widgetSnapshotProjectorKeepsFocusOnlyWhenFilterInactive() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makeFocusFilterTask(id: "focus-a", title: "Focus task A"),
      makeFocusFilterTask(id: "extra-c", title: "Non-focus task C"),
    ],
    localChangeSequence: 1
  )
  let currentFocus = CurrentFocusPlan(
    date: "2026-05-22",
    taskIDs: ["focus-a"],
    briefing: nil,
    timezone: "UTC",
    localChangeSequence: 1
  )
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })

  // Default: filter is .inactive — projector keeps the pre-existing focus-only behavior
  // when a focus plan is set, so non-focus tasks don't surface on the widget.
  let snapshot = projector.snapshot(today: today, currentFocus: currentFocus, timezone: nil)

  #expect(snapshot.focusTasks.map(\.id) == ["focus-a"])
  #expect(!snapshot.focusTasks.map(\.id).contains("extra-c"))
}

@Test
func widgetSnapshotProjectorShowsAllTasksWhenFilterActiveButShowFlagIsTrue() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makeFocusFilterTask(id: "focus-a", title: "Focus task A"),
      makeFocusFilterTask(id: "extra-c", title: "Non-focus task C"),
    ],
    localChangeSequence: 1
  )
  let currentFocus = CurrentFocusPlan(
    date: "2026-05-22",
    taskIDs: ["focus-a"],
    briefing: nil,
    timezone: "UTC",
    localChangeSequence: 1
  )
  let filter = FocusFilterConfiguration(activeProfileID: "Lorvex Focus", showNonFocusTasks: true)
  let projector = WidgetSnapshotProjector(calendar: Calendar(identifier: .gregorian), now: { now })

  let snapshot = projector.snapshot(
    today: today,
    currentFocus: currentFocus,
    timezone: nil,
    focusFilter: filter
  )

  #expect(snapshot.focusTasks.map(\.id).contains("extra-c"))
  #expect(snapshot.focusTasks.map(\.id).contains("focus-a"))
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

  let config = FocusFilterConfiguration(activeProfileID: "Deep Work", showNonFocusTasks: false)
  let saved = try await store.save(config)

  let loaded = try await store.load()
  #expect(loaded.activeProfileID == "Deep Work")
  #expect(loaded.showNonFocusTasks == false)
  #expect(loaded.isActive == true)
  #expect(saved.revision == 1)
}

@Test
func focusFilterStoreResetRestoresInactiveState() async throws {
  let root = focusFilterTempDirectory()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = FocusFilterStore(
    managedDatabasePath: root.appendingPathComponent("db.sqlite").path)

  _ = try await store.save(
    FocusFilterConfiguration(activeProfileID: "Work", showNonFocusTasks: true))
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

  async let firstSave = first.save(
    FocusFilterConfiguration(activeProfileID: "First", showNonFocusTasks: false))
  async let secondSave = second.save(
    FocusFilterConfiguration(activeProfileID: "Second", showNonFocusTasks: true))
  let (savedFirst, savedSecond) = try await (firstSave, secondSave)
  let revisions = [savedFirst.revision, savedSecond.revision].sorted()

  #expect(revisions == [1, 2])
  let final = try await first.loadState()
  #expect(final.revision == 2)
  #expect(["First", "Second"].contains(final.configuration.activeProfileID))
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
      FocusFilterConfiguration(activeProfileID: "Stale private profile"))
  }
  #expect(try await freshStore.loadState() == inactive)
}

// MARK: - Helpers

private func makeFocusFilterTask(id: String, title: String) -> LorvexTask {
  LorvexTask(
    id: id,
    title: title,
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: []
  )
}

private func focusFilterTempDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "lorvex-focus-filter-\(UUID().uuidString)", isDirectory: true)
}
