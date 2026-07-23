import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

struct CloudSyncInvalidChangeCursor: Error, Sendable, Equatable {}

struct CloudSyncCursorRecoveryPrepared: Error, LocalizedError, Sendable, Equatable {
  var errorDescription: String? {
    "CloudKit change history expired; Lorvex prepared a full retry from the beginning."
  }
}

struct CloudSyncAuthoritativePullResult: Sendable {
  var fetched: Int
  var report: InboundApplyReport
  var reachedTerminal: Bool
}

struct CloudSyncAuthoritativeRecordFailureRecovery: Error, Sendable {
  let failure: CloudSyncPerRecordFetchFailure
}

extension CloudSyncEngineCoordinator {
  func prepareAuthoritativeSnapshot(
    sync: any EnvelopeSyncServicing, boundary: CloudTraversalBoundary,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> AuthoritativeSnapshotSession {
    var session = try sync.beginAuthoritativeSnapshot(boundary: boundary)
    switch session.phase {
    case .preparing:
      // Session creation atomically fenced the pre-session queue in SQLite.
      // Never blanket-fence again here: active rows now represent user/MCP
      // writes made while the snapshot was in flight, including across a cursor
      // restart, and finalization must replay them on top of the remote baseline.
      try await pusher.publishTraversalWitness(
        context: context, expectation: expectation,
        traversalIdentifier: session.sessionToken,
        boundaryGuard: boundaryGuard)
      try sync.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)
      session = try requireAuthoritativeSession(
        sync: sync, boundary: boundary, token: session.sessionToken)

    case .ready:
      // `preparing -> ready` is committed only after the immutable witness save,
      // but re-asserting it makes recovery robust to a server-side retry/read gap.
      try await pusher.publishTraversalWitness(
        context: context, expectation: expectation,
        traversalIdentifier: session.sessionToken,
        boundaryGuard: boundaryGuard)

    case .pulling:
      let state = try sync.cloudTraversalState(
        accountIdentifier: boundary.accountIdentifier,
        zoneIdentifier: boundary.zoneIdentifier)
      guard let progress = state.progress,
        progress.traversalIdentifier == session.sessionToken
      else { throw AuthoritativeSnapshotError.sessionBoundaryMismatch }
      if !progress.observedTraversalWitness {
        try await pusher.publishTraversalWitness(
          context: context, expectation: expectation,
          traversalIdentifier: session.sessionToken,
          boundaryGuard: boundaryGuard)
      }
    }
    return session
  }

  func prepareInWindowBaselineRecovery(
    sync: any EnvelopeSyncServicing, boundary: CloudTraversalBoundary,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool,
    tombstoneCompactionCutoff: String? = nil
  ) async throws {
    var state = try sync.cloudTraversalState(
      accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
    if state.progress?.boundary != boundary || state.progress?.mode != .baseline {
      if let progress = state.progress {
        try sync.cancelCloudTraversal(
          boundary: progress.boundary,
          traversalIdentifier: progress.traversalIdentifier)
      }
      let traversalIdentifier = CloudSyncGenerationNaming.newGenerationID()
      _ = try sync.beginCloudTraversal(
        boundary: boundary, traversalIdentifier: traversalIdentifier,
        start: .baseline)
      state = try sync.cloudTraversalState(
        accountIdentifier: boundary.accountIdentifier,
        zoneIdentifier: boundary.zoneIdentifier)
    }
    guard let progress = state.progress, progress.boundary == boundary,
      progress.mode == .baseline, progress.startingChangeToken == nil
    else { throw CloudTraversalStateError.traversalBoundaryMismatch }

    // The standing marker remains set until the terminal page commits. Thus a
    // crash between any of these idempotent steps repeats the whole preparation
    // instead of falling back to an incremental cursor.
    _ = try sync.enqueueFullResyncBackfill(
      tombstoneCompactionCutoff: tombstoneCompactionCutoff)
    try await pusher.publishTraversalWitness(
      context: context, expectation: expectation,
      traversalIdentifier: progress.traversalIdentifier,
      boundaryGuard: boundaryGuard)
  }

  func warnOverWindowSnapshotReEnrollment(
    sync: any EnvelopeSyncServicing
  ) async {
    let message =
      "This database lacks server-confirmed traversal coverage through the "
      + "\(SyncNaming.tombstoneMaxRetentionDays)-day delete-recovery cutoff. "
      + "The complete current iCloud snapshot is being adopted as the source of truth; "
      + "edits made beyond the recovery window may be dropped."
    Self.log.notice("CloudSync authoritative over-window recovery: \(message, privacy: .public)")
    try? await (sync as? any LorvexSystemServicing)?.appendDiagnosticLog(
      source: "cloudsync.over_window.snapshot_reenroll", level: "warn",
      message: message, details: nil)
  }

  func restartAuthoritativeSnapshotAfterInvalidCursor(
    sync: any EnvelopeSyncServicing, boundary: CloudTraversalBoundary,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws {
    _ = try sync.restartAuthoritativeSnapshot()
    _ = try await prepareAuthoritativeSnapshot(
      sync: sync, boundary: boundary, context: context,
      expectation: expectation, boundaryGuard: boundaryGuard)
  }

  func pullOneAuthoritativeSnapshotPage(
    sync: any EnvelopeSyncServicing, session: AuthoritativeSnapshotSession,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: @escaping @Sendable () async -> Bool
  ) async throws -> CloudSyncAuthoritativePullResult {
    let boundary = session.boundary
    let state = try sync.cloudTraversalState(
      accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
    guard let progress = state.progress,
      progress.boundary == boundary,
      progress.traversalIdentifier == session.sessionToken,
      progress.mode == .baseline,
      progress.startingChangeToken == nil
    else { throw AuthoritativeSnapshotError.sessionBoundaryMismatch }

    let cursor = progress.continuationToken.map {
      CloudSyncChangeCursor(
        accountIdentifier: boundary.accountIdentifier,
        zoneName: boundary.zoneIdentifier, generationEpoch: boundary.generation,
        generationID: boundary.generationIdentifier,
        readyWitness: boundary.readyWitness, serverChangeTokenData: $0)
    }
    let batch = try await fetcher.fetchChanges(
      after: cursor, context: context,
      traversalWitnessIdentifier: session.sessionToken,
      boundaryGuard: boundaryGuard)
    try batch.assertPreservesGenerationMarkers(context: context)
    guard !batch.discardedInvalidCheckpointToken else {
      throw CloudSyncInvalidChangeCursor()
    }
    if let failure = batch.perRecordFailure {
      if failure.kind == .persistent {
        let reachedThreshold = try sync.recordRemoteChangeFetchFailure(
          checkpointKey:
            "private|\(context.zoneName)|\(failure.checkpointFingerprint)|authoritative-withheld",
          threshold: Self.perRecordFetchFailureReseedThreshold)
        if reachedThreshold {
          throw CloudSyncAuthoritativeRecordFailureRecovery(failure: failure)
        }
      }
      throw failure
    }

    var staged: [AuthoritativeSnapshotRemoteRecord] = []
    staged.reserveCapacity(batch.records.count)
    for record in batch.records {
      switch CloudSyncEnvelopeRecord.decode(record) {
      case .decoded(let envelope):
        staged.append(
          AuthoritativeSnapshotRemoteRecord(
            recordName: record.recordID.recordName, state: .decoded,
            envelope: envelope,
            serverModifiedAt: record.modificationDate.map(
              SyncTimestampFormat.formatSyncTimestamp)))
      case .unknownEntityType(let raw):
        staged.append(
          AuthoritativeSnapshotRemoteRecord(
            recordName: record.recordID.recordName, state: .unknown,
            envelope: nil, rawEnvelope: raw,
            serverModifiedAt: record.modificationDate.map(
              SyncTimestampFormat.formatSyncTimestamp)))
      case .corrupt:
        staged.append(
          AuthoritativeSnapshotRemoteRecord(
            recordName: record.recordID.recordName, state: .corrupt,
            envelope: nil,
            serverModifiedAt: record.modificationDate.map(
              SyncTimestampFormat.formatSyncTimestamp)))
      case .foreign:
        if !Self.isValidatedGenerationMarker(record) {
          // A foreign type occupying a Lorvex deterministic record-name slot is
          // not evidence that the canonical entity is absent. Retain the slot as
          // corrupt snapshot debt so terminal reconciliation fails closed instead
          // of physically pruning a same-name local row. Validated generation
          // markers share this page but are control-plane records, not inventory.
          staged.append(
            AuthoritativeSnapshotRemoteRecord(
              recordName: record.recordID.recordName, state: .corrupt,
              envelope: nil,
              serverModifiedAt: record.modificationDate.map(
                SyncTimestampFormat.formatSyncTimestamp)))
        }
      }
    }

    let observedTraversal = batch.observedTraversalWitnessIdentifiers.contains(
      session.sessionToken) ? session.sessionToken : nil
    let observedTraversalServerTime = batch.traversalWitnessServerModificationDates[
      session.sessionToken
    ].map(SyncTimestampFormat.formatSyncTimestamp)
    let observation = try CloudTraversalPageObservation(
      generationRootIdentifier: batch.observedGenerationRoot
        ? boundary.generationIdentifier : nil,
      readyWitness: batch.observedReadyWitness,
      traversalWitnessIdentifier: observedTraversal,
      traversalWitnessServerTime: observedTraversalServerTime)
    let page = try CloudTraversalPageCommit(
      pageIndex: progress.nextPageIndex,
      continuationToken: batch.serverChangeTokenData,
      moreComing: batch.moreComing, observation: observation)

    if batch.moreComing {
      try sync.stageAuthoritativeSnapshotContinuationPage(
        records: staged, deletedRecordNames: batch.deletedRecordNames,
        sessionToken: session.sessionToken, boundary: boundary,
        traversalIdentifier: session.sessionToken, page: page)
      return CloudSyncAuthoritativePullResult(
        fetched: batch.records.count, report: InboundApplyReport(),
        reachedTerminal: false)
    }

    // A terminal baseline without a cursor cannot hand off safely to incremental
    // sync; production CloudKit always provides one, so fail closed on a broken
    // transport/test implementation rather than repeatedly treating it as done.
    guard batch.serverChangeTokenData != nil else {
      throw CloudSyncInvalidChangeCursor()
    }
    let finalized = try sync.finalizeAuthoritativeSnapshotTerminalPage(
      records: staged, deletedRecordNames: batch.deletedRecordNames,
      sessionToken: session.sessionToken, boundary: boundary,
      traversalIdentifier: session.sessionToken, page: page)
    var report = InboundApplyReport()
    report.applied = finalized.removedLocalEntities + finalized.replayedRemoteRecords
    report.deferredUnknownType = finalized.deferredUnknownTypeRecords
    report.appliedEntityTypes = finalized.changedEntityTypes
    return CloudSyncAuthoritativePullResult(
      fetched: batch.records.count, report: report, reachedTerminal: true)
  }

  private func requireAuthoritativeSession(
    sync: any EnvelopeSyncServicing, boundary: CloudTraversalBoundary, token: String
  ) throws -> AuthoritativeSnapshotSession {
    guard let session = try sync.authoritativeSnapshotSession(),
      session.boundary == boundary, session.sessionToken == token
    else { throw AuthoritativeSnapshotError.sessionBoundaryMismatch }
    return session
  }

  private static func isValidatedGenerationMarker(_ record: CKRecord) -> Bool {
    let name = record.recordID.recordName
    return (name == CloudSyncGenerationRootRecord.recordName
      && record.recordType == CloudSyncGenerationRootRecord.recordType)
      || (name == CloudSyncGenerationSealRecord.recordName
        && record.recordType == CloudSyncGenerationSealRecord.recordType)
      || (name.hasPrefix(CloudSyncTraversalWitnessRecord.recordNamePrefix)
        && record.recordType == CloudSyncTraversalWitnessRecord.recordType)
  }
}
