@preconcurrency import CloudKit
import Foundation
import LorvexCore
import LorvexSync
import os

/// Opaque proof of the exact local and remote boundary for which the host asks
/// the user to authorize a re-upload. Hosts can route the request by pause
/// reason but cannot construct or retarget it.
public struct CloudSyncAccountAdoptionRequest: Sendable, Equatable {
  public var pauseReason: CloudSyncPauseReason { pauseSnapshot.reason }

  let pauseSnapshot: CloudSyncPauseSnapshot
  let accountIdentifier: String
  let databaseInstanceIdentifier: String
  let sourceBinding: CloudTraversalAccountBinding?
  let recordedAccountIdentifier: String?
  let deletionGeneration: Int?
}

extension CloudSyncEngineCoordinator {
  /// Account notifications never imply consent to copy this database into a
  /// different Apple ID. Same-account refreshes may clear only the exact pause
  /// event they observed; unfinished adoption and deletion gates remain closed.
  @discardableResult
  public func handleAccountChange() async throws -> AccountChangeBackfillDecision {
    try await withSerializedOperation {
      let previous = try await accountIdentityStore.loadLastAccountIdentifier()
      let current = await accountIdentifier.currentAccountIdentifier()
      let pause = try await accountPauseStore.loadPauseSnapshot()
      if pause?.reason == .userDeletedZone { return .suppressedUserDeletedZone }
      if pause?.reason == .adoptionInProgress || pause?.reason == .backfillFailed {
        return .backfillFailed
      }

      guard let current else {
        // An account-change notification is a new authorization boundary even
        // when the durable reason already has the same value. Mint a fresh
        // revision so a dialog prepared before a B -> unavailable -> B round
        // trip cannot consume stale consent.
        try await accountPauseStore.savePauseReason(.accountChanged)
        await pusher.clearAllRecordSystemFieldsCache()
        return .suppressedDifferentAccount
      }
      guard let previous else {
        // The normal start gate reconciles the SQLite binding before deciding
        // whether this is a genuine first binding.
        return .backfilled
      }
      guard previous == current else {
        try await accountPauseStore.savePauseReason(.accountChanged)
        await pusher.clearAllRecordSystemFieldsCache()
        return .suppressedDifferentAccount
      }

      if let pause, pause.reason == .accountChanged {
        _ = try await accountPauseStore.compareAndSetPauseSnapshot(
          expected: pause, replacement: nil)
      }
      return .backfilled
    }
  }

  /// Prepare the exact account/DB/pause boundary before the confirmation dialog
  /// is shown. A later account switch, database replacement, binding adoption,
  /// repeated pause event, or newer remote deletion invalidates this capability.
  public func makeAccountAdoptionRequest(
    sync: any EnvelopeSyncServicing,
    expectedPauseReason: CloudSyncPauseReason
  ) async -> CloudSyncAccountAdoptionRequest? {
    do {
      return try await withSerializedOperation {
        try await makeAccountAdoptionRequestUnlocked(
          sync: sync, expectedPauseReason: expectedPauseReason,
          requireRecordedAccountMatch: false)
      }
    } catch {
      Self.log.error(
        "CloudSync could not prepare an account-bound adoption request: \(error.localizedDescription, privacy: .private)")
      return nil
    }
  }

  /// A Live-mode toggle has no second confirmation dialog, so it may recreate a
  /// deleted namespace only for the exact account that owns the durable deletion
  /// state. A different account must use the explicit adoption confirmation.
  public func makeSameAccountDeletedZoneReenableRequest(
    sync: any EnvelopeSyncServicing
  ) async -> CloudSyncAccountAdoptionRequest? {
    do {
      return try await withSerializedOperation {
        try await makeAccountAdoptionRequestUnlocked(
          sync: sync, expectedPauseReason: .userDeletedZone,
          requireRecordedAccountMatch: true)
      }
    } catch {
      Self.log.error(
        "CloudSync could not prepare the deleted-zone re-enable request: \(error.localizedDescription, privacy: .private)")
      return nil
    }
  }

  @discardableResult
  public func confirmBackfillIntoCurrentAccount(
    sync: any EnvelopeSyncServicing,
    request: CloudSyncAccountAdoptionRequest
  ) async -> Bool {
    guard request.pauseReason != .userDeletedZone else { return false }
    return await confirmAccountAdoption(
      sync: sync, request: request, authorization: { true })
  }

  /// Dedicated deleted-zone re-enable. `authorization` carries the host's local
  /// deletion epoch; the opaque request independently binds account, database,
  /// pause revision, and remote deletion generation.
  @discardableResult
  public func confirmDeletedZoneReenable(
    sync: any EnvelopeSyncServicing,
    request: CloudSyncAccountAdoptionRequest,
    authorization: @escaping @Sendable () async -> Bool
  ) async -> Bool {
    guard request.pauseReason == .userDeletedZone else { return false }
    return await confirmAccountAdoption(
      sync: sync, request: request, authorization: authorization)
  }

  private func confirmAccountAdoption(
    sync: any EnvelopeSyncServicing,
    request: CloudSyncAccountAdoptionRequest,
    authorization: @escaping @Sendable () async -> Bool
  ) async -> Bool {
    do {
      return try await withSerializedOperation {
        guard await authorization() else { return false }
        return try await confirmAccountAdoptionUnlocked(sync: sync, request: request)
      }
    } catch {
      Self.log.error(
        "CloudSync explicit account adoption failed closed: \(error.localizedDescription, privacy: .private)")
      return false
    }
  }

  private func makeAccountAdoptionRequestUnlocked(
    sync: any EnvelopeSyncServicing,
    expectedPauseReason: CloudSyncPauseReason,
    requireRecordedAccountMatch: Bool
  ) async throws -> CloudSyncAccountAdoptionRequest? {
    guard try await accountChecker.checkAccountStatus() == .available,
      let pause = try await accountPauseStore.loadPauseSnapshot(),
      pause.reason == expectedPauseReason,
      let current = await accountIdentifier.currentAccountIdentifier(),
      let databaseInstanceID = try sync.databaseInstanceIdentifier()
    else { return nil }
    let sourceBinding = try sync.cloudTraversalAccountBindingForAdoption()
    let recorded = try await accountIdentityStore.loadLastAccountIdentifier()
    if requireRecordedAccountMatch, recorded != current { return nil }

    let deletionGeneration: Int?
    if expectedPauseReason == .userDeletedZone {
      guard case .deleted(let generation, _, _)? =
        try await pusher.currentZoneGenerationState()
      else { return nil }
      deletionGeneration = generation
    } else if case .deleted(let generation, _, _)? =
      try? await pusher.currentZoneGenerationState()
    {
      // A retry that crashed after entering `adoptionInProgress` but before its
      // local reset still needs the deleted-lineage reset. For other adoption
      // reasons this read is advisory: a transient generation read must not
      // prevent the user from preparing the account-bound capability; the
      // rebuild performs the authoritative read after consent and fails closed.
      deletionGeneration = generation
    } else {
      deletionGeneration = nil
    }

    // Every read above can suspend. Re-read the complete local boundary before
    // issuing the capability so it represents one coherent point in time.
    guard await accountIdentifier.currentAccountIdentifier() == current,
      try sync.databaseInstanceIdentifier() == databaseInstanceID,
      try sync.cloudTraversalAccountBindingForAdoption() == sourceBinding,
      try await accountIdentityStore.loadLastAccountIdentifier() == recorded,
      try await accountPauseStore.loadPauseSnapshot() == pause
    else { return nil }
    if let deletionGeneration {
      guard case .deleted(let currentGeneration, _, _)? =
        try await pusher.currentZoneGenerationState(),
        currentGeneration == deletionGeneration
      else { return nil }
    }
    return CloudSyncAccountAdoptionRequest(
      pauseSnapshot: pause, accountIdentifier: current,
      databaseInstanceIdentifier: databaseInstanceID,
      sourceBinding: sourceBinding,
      recordedAccountIdentifier: recorded,
      deletionGeneration: deletionGeneration)
  }

  private func confirmAccountAdoptionUnlocked(
    sync: any EnvelopeSyncServicing,
    request: CloudSyncAccountAdoptionRequest
  ) async throws -> Bool {
    guard try await accountChecker.checkAccountStatus() == .available,
      await accountIdentifier.currentAccountIdentifier() == request.accountIdentifier,
      try sync.databaseInstanceIdentifier() == request.databaseInstanceIdentifier,
      try sync.cloudTraversalAccountBindingForAdoption() == request.sourceBinding,
      try await accountIdentityStore.loadLastAccountIdentifier()
        == request.recordedAccountIdentifier,
      try await accountPauseStore.loadPauseSnapshot() == request.pauseSnapshot
    else { return false }
    if let deletionGeneration = request.deletionGeneration {
      guard case .deleted(let currentGeneration, _, _)? =
        try await pusher.currentZoneGenerationState(),
        currentGeneration == deletionGeneration
      else { return false }
    }

    let transition = try await accountPauseStore.compareAndSetPauseSnapshot(
      expected: request.pauseSnapshot, replacement: .adoptionInProgress)
    guard case .applied(let adoptionSnapshot?) = transition else { return false }

    do {
      return try await executeAccountAdoption(
        sync: sync, request: request, adoptionSnapshot: adoptionSnapshot)
    } catch {
      await markAdoptionFailedIfNeeded(
        expected: adoptionSnapshot, after: error)
      throw error
    }
  }

  private func executeAccountAdoption(
    sync: any EnvelopeSyncServicing,
    request: CloudSyncAccountAdoptionRequest,
    adoptionSnapshot: CloudSyncPauseSnapshot
  ) async throws -> Bool {
    let current = request.accountIdentifier
    let databaseInstanceID = request.databaseInstanceIdentifier
    await pusher.clearAllRecordSystemFieldsCache()

    // The request-time generation read is advisory for ordinary/backfill
    // adoption so a transient CloudKit failure cannot block consent. Re-read
    // authoritatively before the first local mutation: a retry may now reveal
    // that the same-account namespace is still deleted and therefore needs the
    // old transport lineage reset before candidate enumeration.
    let state = try await pusher.currentZoneGenerationState()
    guard await accountIdentifier.currentAccountIdentifier() == current else {
      throw CloudSyncAccountBoundaryCrossed()
    }
    if let expectedDeletionGeneration = request.deletionGeneration {
      guard case .deleted(let actualDeletionGeneration, _, _)? = state,
        actualDeletionGeneration == expectedDeletionGeneration
      else { throw CloudSyncAccountBoundaryCrossed() }
    }
    let adoptionMode: CloudTraversalAccountAdoptionMode
    if case .deleted? = state {
      adoptionMode = .sameAccountDeletedZoneReupload
    } else {
      adoptionMode = .accountSwitchOrRetry
    }
    let preparedBinding = try sync.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: current, mode: adoptionMode)
    guard preparedBinding.accountIdentifier == current,
      preparedBinding.databaseInstanceIdentifier == databaseInstanceID,
      await accountIdentifier.currentAccountIdentifier() == current
    else { throw CloudSyncAccountBoundaryCrossed() }

    let authorityFloor = try sync.observedCloudGenerationAuthorityFloor(
      forAccountIdentifier: current)
    if let state, state.epoch >= (authorityFloor ?? 0) {
      _ = try sync.recordObservedCloudGenerationAuthority(
        forAccountIdentifier: current, generation: state.epoch)
    }
    let descriptor = try await rebuildGeneration(
      sync: sync, accountIdentifier: current,
      databaseInstanceIdentifier: databaseInstanceID,
      startingState: state, allowFromDeleted: true,
      minimumGenerationFloor: max(authorityFloor ?? 0, state?.epoch ?? 0))
    guard await accountIdentifier.currentAccountIdentifier() == current,
      case .ready(let currentDescriptor, _, _) =
        try await pusher.currentZoneGenerationState(),
      currentDescriptor == descriptor,
      let terminalBinding = try sync.cloudTraversalAccountBinding(),
      terminalBinding.accountIdentifier == current,
      terminalBinding.databaseInstanceIdentifier == databaseInstanceID,
      try sync.currentGenerationSnapshotStaging() == nil
    else { throw CloudSyncAccountBoundaryCrossed() }

    // The external fingerprint is a repairable mirror. Publish it only after
    // exact remote-ready and SQLite finalization proof; a failed adoption must
    // never make normal startup believe the new account was already complete.
    try await accountIdentityStore.saveLastAccountIdentifier(current)
    guard await accountIdentifier.currentAccountIdentifier() == current,
      try await accountIdentityStore.loadLastAccountIdentifier() == current
    else { throw CloudSyncAccountBoundaryCrossed() }
    guard case .applied(nil) = try await accountPauseStore.compareAndSetPauseSnapshot(
      expected: adoptionSnapshot, replacement: nil)
    else { throw CloudSyncAccountBoundaryCrossed() }
    return true
  }

  private func markAdoptionFailedIfNeeded(
    expected adoptionSnapshot: CloudSyncPauseSnapshot,
    after error: any Error
  ) async {
    do {
      let reason = await adoptionFailurePauseReason(error)
      _ = try await accountPauseStore.compareAndSetPauseSnapshot(
        expected: adoptionSnapshot, replacement: reason)
    } catch {
      Self.log.error(
        "CloudSync could not persist the failed adoption phase: \(error.localizedDescription, privacy: .private)")
    }
  }

  private func adoptionFailurePauseReason(
    _ error: any Error
  ) async -> CloudSyncPauseReason {
    if error is CloudSyncAccountBoundaryCrossed { return .accountChanged }
    if let partial = error as? CloudSyncPartialCycleFailure {
      return await adoptionFailurePauseReason(partial.underlyingError)
    }
    if let cloudKit = error as? CKError, cloudKit.code == .userDeletedZone {
      return .userDeletedZone
    }
    let nsError = error as NSError
    if nsError.domain == CKErrorDomain,
      CKError.Code(rawValue: nsError.code) == .userDeletedZone
    {
      return .userDeletedZone
    }
    if case .deleted? = try? await pusher.currentZoneGenerationState() {
      return .userDeletedZone
    }
    return .backfillFailed
  }
}
