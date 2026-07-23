import Foundation
import LorvexCore
import os

private struct CloudSyncDeletionZonesRemain: LocalizedError {
  var errorDescription: String? { "Lorvex generation zones remain after cleanup" }
}

/// Failure raised while publishing or physically completing a CloudKit deletion.
public enum CloudSyncCloudDataDeletionError: Error, Equatable {
  case accountUnavailable(CloudKitAccountAvailability)
  /// The fleet-visible `.deleted` barrier is durable, but one or more physical
  /// zone deletions remain for the next maintenance retry.
  case cleanupIncomplete(String)
}

extension CloudSyncEngineCoordinator {
  /// Publish a permanent default-zone `.deleted` barrier, then delete every
  /// Lorvex generation zone. The singleton survives the wipe: absence means
  /// true bootstrap, while `.deleted` requires explicit re-enable consent.
  public func deleteAllCloudData(sync: any EnvelopeSyncServicing) async throws {
    try await withSerializedOperation {
      try await deleteAllCloudDataUnlocked(sync: sync)
    }
  }

  /// Resume only the physical cleanup authorized by a durable remote `.deleted`
  /// barrier. This maintenance path is safe while ordinary sync is paused/off:
  /// it never creates a zone, uploads a record, clears the consent pause, or
  /// changes a ready/rebuilding generation. App launch/foreground triggers may
  /// call it repeatedly; returning `false` means no deletion pause was standing.
  @discardableResult
  public func retryPendingCloudDataDeletionCleanup(
    sync: any EnvelopeSyncServicing
  ) async throws -> Bool {
    try await withSerializedOperation {
      try await retryPendingCloudDataDeletionCleanupUnlocked(sync: sync)
    }
  }

  private func deleteAllCloudDataUnlocked(
    sync: any EnvelopeSyncServicing
  ) async throws {
    let availability: CloudKitAccountAvailability
    do {
      availability = try await accountChecker.checkAccountStatus()
    } catch {
      throw CloudSyncCloudDataDeletionError.accountUnavailable(.couldNotDetermine)
    }
    guard availability == .available else {
      throw CloudSyncCloudDataDeletionError.accountUnavailable(availability)
    }
    guard let account = await accountIdentifier.currentAccountIdentifier() else {
      throw CloudSyncCloudDataDeletionError.accountUnavailable(.couldNotDetermine)
    }
    let identityReader = accountIdentifier
    let boundaryGuard: @Sendable () async -> Bool = {
      await identityReader.currentAccountIdentifier() == account
    }

    // Persist the deletion target under the local consent gate before any
    // remote mutation. A crash in this window leaves ordinary sync stopped and
    // gives launch maintenance an exact account boundary; it cannot accidentally
    // finish account A's deletion after the user signs into account B.
    let priorAccount = try await accountIdentityStore.loadLastAccountIdentifier()
    let priorPause = try await accountPauseStore.loadPauseReason()
    try await accountPauseStore.savePauseReason(.userDeletedZone)
    do {
      try await accountIdentityStore.saveLastAccountIdentifier(account)
    } catch {
      if let priorPause {
        try? await accountPauseStore.savePauseReason(priorPause)
      } else {
        try? await accountPauseStore.clearPauseReason()
      }
      throw error
    }

    // Remote fleet barrier second, physical cleanup last. Once `.deleted` is
    // published it is never rolled back because a zone delete failed; that
    // would reopen ordinary writers over a partial wipe.
    let deletedState: CloudSyncZoneGenerationState
    do {
      // Deletion is a valid first CloudKit operation (for example after an
      // install restored local data while ordinary sync stayed off). Bind an
      // unclaimed physical database to the verified current account before
      // reading its anti-rollback generation floor. Existing bindings remain
      // fail-closed across account or database-lineage mismatches.
      if let databaseInstanceID = try sync.databaseInstanceIdentifier() {
        try establishTraversalBinding(
          sync: sync, accountIdentifier: account,
          databaseInstanceIdentifier: databaseInstanceID)
      }
      let localAuthorityFloor = try sync.observedCloudGenerationAuthorityFloor(
        forAccountIdentifier: account) ?? 0
      deletedState = try await pusher.markCloudDataDeleted(
        atLeast: localAuthorityFloor, boundaryGuard: boundaryGuard)
    } catch {
      // Restore a previous different binding before lifting the pause. If that
      // restore itself fails, fail closed behind `.userDeletedZone`; proceeding
      // with an unverified account identity could sync into the wrong account.
      var identityRestored = true
      if let priorAccount, priorAccount != account {
        do {
          try await accountIdentityStore.saveLastAccountIdentifier(priorAccount)
        } catch {
          identityRestored = false
        }
      }
      if identityRestored {
        if let priorPause {
          try? await accountPauseStore.savePauseReason(priorPause)
        } else {
          try? await accountPauseStore.clearPauseReason()
        }
      }
      throw error
    }

    try await cleanDeletedGenerationZones(
      deletedState: deletedState, accountIdentifier: account,
      boundaryGuard: boundaryGuard, sync: sync)
    await pusher.clearAllRecordSystemFieldsCache()
    Self.log.notice(
      "CloudSync published the persistent deleted barrier and removed every Lorvex generation zone."
    )
  }

  func retryPendingCloudDataDeletionCleanupUnlocked(
    sync: any EnvelopeSyncServicing
  ) async throws -> Bool {
    guard try await accountPauseStore.loadPauseReason() == .userDeletedZone else {
      return false
    }
    guard (try? await accountChecker.checkAccountStatus()) == .available,
      let account = await accountIdentifier.currentAccountIdentifier(),
      let boundAccount = try await accountIdentityStore.loadLastAccountIdentifier(),
      boundAccount == account
    else { return true }
    let identityReader = accountIdentifier
    let boundaryGuard: @Sendable () async -> Bool = {
      await identityReader.currentAccountIdentifier() == account
    }

    // A pause can survive an iCloud-account switch. The remote singleton is the
    // authorization: only an exact `.deleted` state permits physical cleanup.
    // A peer that explicitly re-enabled sync has already moved it to rebuilding
    // or ready, so this old paused device touches no generation zone.
    guard case .deleted? = try await pusher.currentZoneGenerationState() else {
      return true
    }
    guard await boundaryGuard() else { return true }
    guard let deletedState = try await pusher.currentZoneGenerationState(),
      case .deleted = deletedState
    else {
      return true
    }
    try await cleanDeletedGenerationZones(
      deletedState: deletedState, accountIdentifier: account,
      boundaryGuard: boundaryGuard, sync: sync)
    await pusher.clearAllRecordSystemFieldsCache()
    return true
  }

  private func cleanDeletedGenerationZones(
    deletedState: CloudSyncZoneGenerationState,
    accountIdentifier account: String,
    boundaryGuard: @escaping @Sendable () async -> Bool,
    sync: any EnvelopeSyncServicing
  ) async throws {
    guard case .deleted = deletedState else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    var names = Set(deletedState.retiredZoneNames)
    var firstFailure: (any Error)?
    do {
      for zone in try await pusher.allRecordZones(boundaryGuard: boundaryGuard)
      where CloudSyncGenerationNaming.isValidZoneName(zone.zoneID.zoneName) {
        names.insert(zone.zoneID.zoneName)
      }
    } catch {
      firstFailure = error
    }

    for zoneName in names.sorted() {
      do {
        try await pusher.deleteRetiredZone(
          zoneName: zoneName, accountIdentifier: account,
          boundaryGuard: boundaryGuard)
        try sync.acknowledgeAuditRetentionZoneDeletion(
          forAccountIdentifier: account, zoneName: zoneName)
        await pusher.clearRecordSystemFieldsCache(
          accountIdentifier: account, zoneName: zoneName)
        try await pusher.finalizeRetiredZoneDeletion(
          zoneName: zoneName, boundaryGuard: boundaryGuard)
      } catch {
        if firstFailure == nil { firstFailure = error }
      }
    }

    // The enumeration is the deletion inventory, so require a second clean
    // observation before calling the namespace empty. This closes both a failed
    // first listing and a zone that appeared during the first delete pass.
    do {
      let remaining = try await pusher.allRecordZones(boundaryGuard: boundaryGuard)
        .filter { CloudSyncGenerationNaming.isValidZoneName($0.zoneID.zoneName) }
      if !remaining.isEmpty, firstFailure == nil {
        firstFailure = CloudSyncDeletionZonesRemain()
      }
    } catch {
      if firstFailure == nil { firstFailure = error }
    }
    if let firstFailure {
      Self.log.error(
        "CloudSync deletion barrier is durable but physical zone cleanup remains: \(firstFailure.localizedDescription, privacy: .private)"
      )
      throw CloudSyncCloudDataDeletionError.cleanupIncomplete(
        firstFailure.localizedDescription)
    }
  }
}
