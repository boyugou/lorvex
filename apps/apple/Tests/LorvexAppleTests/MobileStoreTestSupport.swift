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

/// A widget publisher that suspends one publication on request, so a test can
/// act while a mutation's post-write surfaces are still publishing. Every
/// publication, held or not, is projected and counted.
@MainActor
final class GatedMobileWidgetSnapshotPublisher: MobileWidgetSnapshotPublishing {
  private var holdsNextPublication = false
  private var heldPublication: CheckedContinuation<Void, Never>?

  /// Publications started so far.
  private(set) var publicationCount = 0

  /// Whether a publication is suspended at the gate.
  var isHolding: Bool { heldPublication != nil }

  /// The next publication suspends until ``release()``; later ones pass through.
  func holdNextPublication() { holdsNextPublication = true }

  func release() {
    heldPublication?.resume()
    heldPublication = nil
  }

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    publicationCount += 1
    if holdsNextPublication {
      holdsNextPublication = false
      await withCheckedContinuation { heldPublication = $0 }
    }
    return try await NoopMobileWidgetSnapshotPublisher().publish(source: source)
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
