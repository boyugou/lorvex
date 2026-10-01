import Foundation
import LorvexCore
import LorvexMobile
import LorvexWidgetKitSupport
import Testing

// MARK: - Recording helper

final class RecordingMobileWidgetSnapshotPublisher: MobileWidgetSnapshotPublishing,
  @unchecked Sendable
{
  struct Publication: Sendable {
    var today: TodaySnapshot
    var habitCatalog: HabitCatalogSnapshot?
    var lists: ListCatalogSnapshot?
  }

  private let lock = NSLock()
  private var recordedPublications: [Publication] = []

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    lock.withLock {
      recordedPublications.append(
        Publication(
          today: source.today,
          habitCatalog: source.habits,
          lists: source.lists))
    }
    return WidgetSnapshotProjector().snapshot(
      storageGeneration: source.storageGeneration,
      logicalDay: source.logicalDay,
      today: source.today,
      timezone: "UTC",
      habitCatalog: source.habits,
      listCatalog: source.lists,
      statsSource: source.stats)
  }

  var publications: [Publication] {
    get async { lock.withLock { recordedPublications } }
  }
}

// MARK: - Helper

@MainActor
func makeStore(
  core: StubCoreService,
  widgetSnapshotPublisher: any MobileWidgetSnapshotPublishing = NoopMobileWidgetSnapshotPublisher(),
  startedAt: Date = Date(timeIntervalSince1970: 0)
) -> MobileStore {
  MobileStore(
    core: core,
    widgetSnapshotPublisher: widgetSnapshotPublisher,
    todayString: { "2026-05-24" },
    now: { startedAt }
  )
}
