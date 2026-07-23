import Foundation
import LorvexCore
@preconcurrency import CloudKit

// MARK: - Protocol

/// Registers a CloudKit database subscription so the app can receive push
/// notifications when records change in the private database.
///
/// Implementations are best-effort — subscription failures are logged but
/// never propagate to the caller.
public protocol CloudSyncSubscribing: Sendable {
  func registerSubscription() async throws
}

/// Failure raised by ``CloudKitCloudSyncSubscriber/registerSubscription()`` when
/// the modify operation returned but reported no per-subscription result for the
/// subscription it was asked to save — the subscription cannot be assumed to
/// exist, so registration fails rather than latching a false success the caller
/// would trust (never re-registering, silently losing push delivery).
public enum CloudSyncSubscriptionError: Error, Equatable {
  case subscriptionSaveResultMissing(String)
}

// MARK: - No-Op

/// A subscriber that takes no action. Used by default when CloudKit push
/// delivery is not configured for the current build.
public struct NoOpCloudSyncSubscriber: CloudSyncSubscribing {
  public init() {}
  public func registerSubscription() async throws {}
}

// MARK: - CloudKit implementation

/// Installs a `CKDatabaseSubscription` on the private CloudKit database so
/// that silent pushes are delivered whenever any record changes.
///
/// Registration is an idempotent CloudKit upsert. The subscription ID is
/// `lorvex-private-db-changes`; re-saving it on launch is cheaper and safer
/// than trusting a process-local defaults flag that can outlive an account,
/// container, or environment change.
public struct CloudKitCloudSyncSubscriber: CloudSyncSubscribing {
  public static let databaseSubscriptionID = "lorvex-private-custom-zone-changes"
  public static let generationControlSubscriptionID = "lorvex-generation-control-changes"

  private let modifier: any CloudKitSubscriptionModifying

  public init(
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier
  ) {
    self.modifier = LiveCloudKitSubscriptionModifier(containerIdentifier: containerIdentifier)
  }

  /// Test seam: inject a fake ``CloudKitSubscriptionModifying`` to drive
  /// `registerSubscription` without CloudKit.
  init(modifier: any CloudKitSubscriptionModifying) {
    self.modifier = modifier
  }

  public func registerSubscription() async throws {
    // CKDatabaseSubscription covers every custom zone but explicitly excludes
    // the private default zone. The generation-control singleton lives in that
    // default zone, so a second query subscription is required for prompt
    // ready/rebuilding/deleted convergence.
    let databaseSubscription = CKDatabaseSubscription(
      subscriptionID: Self.databaseSubscriptionID)
    let generationSubscription = CKQuerySubscription(
      recordType: CloudSyncZoneEpochRecord.recordType,
      predicate: NSPredicate(value: true),
      subscriptionID: Self.generationControlSubscriptionID,
      options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
    generationSubscription.zoneID = CloudSyncZoneEpochRecord.homeZoneID

    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.shouldSendContentAvailable = true
    databaseSubscription.notificationInfo = notificationInfo
    generationSubscription.notificationInfo = notificationInfo

    // `modifySubscriptions` can return as a successful OPERATION while the
    // individual subscription save failed (partial failure, per-subscription
    // rejection). Discarding `saveResults` would let the caller latch
    // `hasRegisteredSubscription = true` over a subscription that was never
    // installed, so silent pushes never arrive and the flag suppresses every
    // retry. Inspect the per-subscription Result and only return success when the
    // subscription actually saved; any other outcome throws so the caller leaves
    // the flag false and the next refresh retries. Mirrors
    // ``CloudKitRecordPusher/ensureZone()``'s per-zone result handling.
    let (saveResults, _) = try await modifier.modifySubscriptions(
      saving: [databaseSubscription, generationSubscription],
      deleting: []
    )
    for identifier in [Self.databaseSubscriptionID, Self.generationControlSubscriptionID] {
      switch saveResults[identifier] {
      case .success:
        break
      case .failure(let error):
        throw error
      case nil:
        throw CloudSyncSubscriptionError.subscriptionSaveResultMissing(identifier)
      }
    }
  }
}

/// Narrow seam over the single `CKDatabase.modifySubscriptions` call
/// ``CloudKitCloudSyncSubscriber`` makes. Production wraps the container's
/// private `CKDatabase`; tests inject a fake returning scripted per-subscription
/// results so the per-item result handling can be verified without CloudKit.
protocol CloudKitSubscriptionModifying: Sendable {
  func modifySubscriptions(
    saving subscriptionsToSave: [CKSubscription],
    deleting subscriptionIDsToDelete: [CKSubscription.ID]
  ) async throws -> (
    saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
    deleteResults: [CKSubscription.ID: Result<Void, any Error>]
  )
}

/// Production ``CloudKitSubscriptionModifying`` over the container's private
/// `CKDatabase`. The database handle is recomputed per call (matching CloudKit's
/// cheap container lookup) so no long-lived `CKDatabase` reference is retained.
struct LiveCloudKitSubscriptionModifier: CloudKitSubscriptionModifying {
  let containerIdentifier: String

  func modifySubscriptions(
    saving subscriptionsToSave: [CKSubscription],
    deleting subscriptionIDsToDelete: [CKSubscription.ID]
  ) async throws -> (
    saveResults: [CKSubscription.ID: Result<CKSubscription, any Error>],
    deleteResults: [CKSubscription.ID: Result<Void, any Error>]
  ) {
    try await CKContainer(identifier: containerIdentifier).privateCloudDatabase
      .modifySubscriptions(saving: subscriptionsToSave, deleting: subscriptionIDsToDelete)
  }
}
