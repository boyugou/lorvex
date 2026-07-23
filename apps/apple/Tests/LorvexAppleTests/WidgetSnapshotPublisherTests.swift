import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@Test
func fileWidgetSnapshotPublisherWritesReadableSnapshotAtomically() async throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-publisher-tests-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL =
    tempDirectory
    .appendingPathComponent("Lorvex", isDirectory: true)
    .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }

  let publisher = FileWidgetSnapshotPublisher(
    snapshotURL: snapshotURL,
    projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
  )
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makePublisherWidgetTask(
        id: "task-widget-file",
        title: "Write widget snapshot",
        priority: .p1,
        dueDate: nil,
        estimatedMinutes: 15
      )
    ],
    localChangeSequence: 1
  )

  let published = try await publisher.publish(today: today, currentFocus: nil)
  let loaded = WidgetSnapshotLoader().loadSnapshot(at: snapshotURL)

  guard case .snapshot(let snapshot) = loaded else {
    Issue.record("Expected the published widget snapshot to be readable")
    return
  }
  #expect(snapshot == published)
  #expect(snapshot.focusTasks.map(\.id) == ["task-widget-file"])
}

@Test
func fileWidgetSnapshotPublisherReloadsGlanceSurfacesOnlyAfterDurableWrite() async throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-reload-tests-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL =
    tempDirectory
    .appendingPathComponent("Lorvex", isDirectory: true)
    .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }

  let snapshotExistedAtReload = LockedBox(false)
  let reloadCount = LockedBox(0)
  let reloadTrigger = WidgetReloadTrigger {
    snapshotExistedAtReload.set(FileManager.default.fileExists(atPath: snapshotURL.path))
    reloadCount.mutate { $0 += 1 }
  }

  let publisher = FileWidgetSnapshotPublisher(
    snapshotURL: snapshotURL,
    projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) }),
    reloadTrigger: reloadTrigger
  )
  let today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [
      makePublisherWidgetTask(
        id: "task-reload",
        title: "Reload glance surfaces",
        priority: .p1,
        dueDate: nil,
        estimatedMinutes: 15
      )
    ],
    localChangeSequence: 1
  )

  _ = try await publisher.publish(today: today, currentFocus: nil)

  #expect(reloadCount.value == 1)
  #expect(snapshotExistedAtReload.value)
}

/// Minimal thread-safe box so the `@Sendable` reload closure can record what it
/// observed without tripping Swift 6 concurrency capture rules.
final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value

  init(_ value: Value) { stored = value }

  var value: Value {
    lock.lock(); defer { lock.unlock() }
    return stored
  }

  func set(_ newValue: Value) {
    lock.lock(); defer { lock.unlock() }
    stored = newValue
  }

  func mutate(_ transform: (inout Value) -> Void) {
    lock.lock(); defer { lock.unlock() }
    transform(&stored)
  }
}

@Test
func fileWidgetSnapshotPublisherCanBeConfiguredFromExplicitEnvironmentPath() {
  let path = "/tmp/lorvex-widget-explicit-\(UUID().uuidString).json"

  let publisher = FileWidgetSnapshotPublisher.configuredFromEnvironment([
    "LORVEX_WIDGET_SNAPSHOT_PATH": path
  ])

  #expect(publisher != nil)
}

@Test
func widgetSnapshotPublisherDefaultsToProductAppGroup() {
  #expect(FileWidgetSnapshotPublisher.configuredAppGroupID([:]) == LorvexProductMetadata.appGroupIdentifier)
  #expect(
    FileWidgetSnapshotPublisher.configuredAppGroupID([
      "LORVEX_WIDGET_APP_GROUP_ID": "group.com.lorvex.test"
    ]) == "group.com.lorvex.test")
}

// The macOS app embeds a widget extension (assembled by package_local.sh), so the
// published App-Group snapshot must carry habits or the macOS Habits widget reads
// back an empty set.
@Test
func fileWidgetSnapshotPublisherIncludesHabits() async throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-habits-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL =
    tempDirectory
    .appendingPathComponent("Lorvex", isDirectory: true)
    .appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }

  let publisher = FileWidgetSnapshotPublisher(
    snapshotURL: snapshotURL,
    projector: WidgetSnapshotProjector(now: { Date(timeIntervalSince1970: 1_779_465_600) })
  )
  let today = TodaySnapshot(focusTitle: "Today", summary: "", tasks: [], localChangeSequence: 1)
  let catalog = HabitCatalogSnapshot(habits: [
    LorvexHabit(
      id: "h1", name: "Meditate", icon: "🧘", color: nil, cue: nil,
      frequencyType: "daily", targetCount: 1, completionsToday: 1,
      totalCompletions: 10, completionRate30d: 0.8, archived: false)
  ])

  let published = try await publisher.publish(
    today: today, currentFocus: nil, habitCatalog: catalog, lists: nil)

  #expect(published.habits.contains { $0.id == "h1" })
}
