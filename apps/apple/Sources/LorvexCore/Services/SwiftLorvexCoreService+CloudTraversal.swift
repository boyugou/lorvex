import GRDB
import LorvexRuntime
import LorvexStore
import LorvexSync

struct CloudTraversalCommitRequest: Sendable {
  let boundary: CloudTraversalBoundary
  let traversalIdentifier: String
  let page: CloudTraversalPageCommit
}

extension SwiftLorvexCoreService {
  public func cloudTraversalAccountBinding() throws -> CloudTraversalAccountBinding? {
    try read { db in try CloudTraversalWitness.accountBinding(db) }
  }

  public func cloudTraversalAccountBindingForAdoption() throws
    -> CloudTraversalAccountBinding?
  {
    try read { db in try CloudTraversalWitness.accountBindingForAdoption(db) }
  }

  @discardableResult
  public func claimCloudTraversalAccount(
    accountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try withCloudTraversalWrite { db in
      try CloudTraversalWitness.claimAccount(db, accountIdentifier: accountIdentifier)
    }
  }

  public func observedCloudGenerationAuthorityFloor(
    forAccountIdentifier accountIdentifier: String
  ) throws -> Int? {
    try read { db in
      try CloudTraversalWitness.observedGenerationAuthorityFloor(
        db, accountIdentifier: accountIdentifier)
    }
  }

  @discardableResult
  public func recordObservedCloudGenerationAuthority(
    forAccountIdentifier accountIdentifier: String, generation: Int
  ) throws -> Int {
    try withCloudTraversalWrite { db in
      try CloudTraversalWitness.recordObservedGenerationAuthority(
        db, accountIdentifier: accountIdentifier, generation: generation)
    }
  }

  @discardableResult
  public func adoptCloudTraversalAccount(
    expectedCurrentAccountIdentifier: String, newAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try withCloudTraversalWrite { db in
      if expectedCurrentAccountIdentifier == newAccountIdentifier {
        return try CloudTraversalWitness.adoptAccount(
          db, expectedCurrentAccountIdentifier: expectedCurrentAccountIdentifier,
          newAccountIdentifier: newAccountIdentifier)
      }
      try AuthoritativeSnapshot.cancel(db)
      let binding = try CloudTraversalWitness.adoptAccount(
        db, expectedCurrentAccountIdentifier: expectedCurrentAccountIdentifier,
        newAccountIdentifier: newAccountIdentifier)
      try SyncCheckpoints.clear(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: expectedCurrentAccountIdentifier))
      try SyncCheckpoints.clear(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: newAccountIdentifier))
      // These are lineage-local recovery hints, not canonical user data. Their
      // keys intentionally do not encode an account, so carrying A's streak or
      // reseed debt into B could escalate B's first failure or trigger a
      // redundant post-adoption rebuild.
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCheckpointKey)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCountKey)
      try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyReseedRequired)
      return binding
    }
  }

  @discardableResult
  public func prepareCloudTraversalForAccountAdoption(
    newAccountIdentifier: String,
    mode: CloudTraversalAccountAdoptionMode
  ) throws -> CloudTraversalAccountBinding {
    try withCloudTraversalWrite { db in
      let sourceBinding = try CloudTraversalWitness.accountBindingForAdoption(db)
      let isOrdinarySameAccountRetry =
        mode == .accountSwitchOrRetry
        && sourceBinding?.accountIdentifier == newAccountIdentifier
      // An explicit adoption supersedes every unfinished authoritative session;
      // its staging and traversal proofs belong to the pre-consent lineage.
      try AuthoritativeSnapshot.cancel(db)
      let adoption = try CloudTraversalWitness.prepareAccountAdoption(
        db, newAccountIdentifier: newAccountIdentifier,
        resetSameAccountDeletedZoneLineage: mode == .sameAccountDeletedZoneReupload)
      if let previous = adoption.previousAccountIdentifier {
        try SyncCheckpoints.clear(
          db,
          key: SyncCheckpoints.keyEnrolledZoneEpoch(
            accountIdentifier: previous))
      }
      try SyncCheckpoints.clear(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: newAccountIdentifier))
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCheckpointKey)
      try SyncCheckpoints.clear(db, key: Self.remoteFetchFailureCountKey)
      // A same-account crash retry must not erase loss discovered after its
      // earlier attempt. The rebuild will consume and clear the reseed marker
      // only after a complete candidate enumeration. Account switches and an
      // exact deleted-zone reupload replace the old transport lineage outright.
      if !isOrdinarySameAccountRetry {
        try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyReseedRequired)
      }
      return adoption.binding
    }
  }

  @discardableResult
  public func rebindCloudTraversalAfterDatabaseInstanceRotation(
    expectedAccountIdentifier: String
  ) throws -> CloudTraversalAccountBinding {
    try withCloudTraversalWrite { db in
      try AuthoritativeSnapshot.cancel(db)
      let rebound = try CloudTraversalWitness.rebindAfterDatabaseInstanceRotation(
        db, expectedAccountIdentifier: expectedAccountIdentifier)
      // Enrollment is proof owned by the old physical database lineage, unlike
      // the account-scoped anti-rollback history retained by `rebindAfter...`.
      // Keeping enrollment can
      // make a restored/clone database whose epoch happens to equal the live
      // descriptor look like the publisher and bypass over-window adoption.
      try SyncCheckpoints.clear(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: expectedAccountIdentifier))
      return rebound
    }
  }

  public func cloudTraversalState(
    accountIdentifier: String, zoneIdentifier: String
  ) throws -> CloudTraversalState {
    try read { db in
      try CloudTraversalWitness.state(
        db, accountIdentifier: accountIdentifier, zoneIdentifier: zoneIdentifier)
    }
  }

  public func cloudInboundCompletenessState(
    boundary: CloudTraversalBoundary
  ) throws -> CloudInboundCompletenessState {
    try read { db in
      try CloudInboundCompleteness.state(db, boundary: boundary)
    }
  }

  @discardableResult
  public func beginCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    start: CloudTraversalStart
  ) throws -> CloudTraversalProgress {
    try withCloudTraversalWrite { db in
      try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier, start: start)
    }
  }

  public func applyInboundTraversalPage(
    _ envelopes: [SyncEnvelope], deferredUnknownTypeRecords: [RawEnvelopeFields] = [],
    cloudReceipts: [InboundCloudRecordReceipt], undecodable: Int,
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    page: CloudTraversalPageCommit,
    inboundObservation: CloudInboundPageObservation
  ) throws -> InboundApplyReport {
    guard undecodable == Set(inboundObservation.corruptRecordNames).count else {
      throw CloudInboundCompletenessError.corruptRecordCountMismatch
    }
    let request = CloudTraversalCommitRequest(
      boundary: boundary, traversalIdentifier: traversalIdentifier, page: page)
    return try withStorageCutoverRetry {
      try self.applyInboundAttempt(
        envelopes, undecodable: undecodable, traversalCommit: request,
        deferredUnknownTypeRecords: deferredUnknownTypeRecords,
        cloudReceiptAccountIdentifier: boundary.accountIdentifier,
        cloudReceipts: cloudReceipts,
        inboundPageObservation: inboundObservation)
    }
  }

  public func stageAuthoritativeSnapshotContinuationPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws {
    guard page.moreComing else { throw CloudTraversalStateError.traversalBoundaryMismatch }
    try withCloudTraversalWrite { db in
      let disposition = try CloudTraversalWitness.preflightPage(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier, page: page)
      guard disposition == .new else {
        guard disposition == .alreadyRecorded else {
          throw CloudTraversalStateError.traversalModeMismatch
        }
        return
      }
      _ = try Self.validateAuthoritativeTraversalBoundary(
        db, sessionToken: sessionToken, boundary: boundary,
        traversalIdentifier: traversalIdentifier)
      try AuthoritativeSnapshot.stagePage(
        db, records: records, deletedRecordNames: deletedRecordNames,
        sessionToken: sessionToken)
      try Self.commitCloudTraversalPageIfPresent(
        db,
        request: CloudTraversalCommitRequest(
          boundary: boundary, traversalIdentifier: traversalIdentifier, page: page))
    }
  }

  public func finalizeAuthoritativeSnapshotTerminalPage(
    records: [AuthoritativeSnapshotRemoteRecord], deletedRecordNames: [String],
    sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String, page: CloudTraversalPageCommit
  ) throws -> AuthoritativeSnapshotReport {
    guard !page.moreComing else { throw CloudTraversalStateError.traversalBoundaryMismatch }
    return try withWrite { db, hlc, deviceId in
      let disposition = try CloudTraversalWitness.preflightPage(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier, page: page)
      if case .alreadyBaselineCompleted = disposition {
        try Self.recordCommittedCloudTraversalDisposition(
          db,
          request: CloudTraversalCommitRequest(
            boundary: boundary, traversalIdentifier: traversalIdentifier, page: page),
          disposition: disposition)
        try Self.finishAuthoritativeTraversalLocalState(db)
        return AuthoritativeSnapshotReport()
      }
      guard disposition == .new else {
        throw CloudTraversalStateError.traversalModeMismatch
      }
      let databaseInstanceIdentifier = try Self.validateAuthoritativeTraversalBoundary(
        db, sessionToken: sessionToken, boundary: boundary,
        traversalIdentifier: traversalIdentifier)
      try AuthoritativeSnapshot.stagePage(
        db, records: records, deletedRecordNames: deletedRecordNames,
        sessionToken: sessionToken)
      let report = try Self.finalizeAuthoritativeSnapshotAndReconcileDerivedState(
        db, service: self, hlc: hlc, deviceId: deviceId,
        sessionToken: sessionToken, databaseInstanceId: databaseInstanceIdentifier)
      try CloudInboundCompleteness.clearAfterAuthoritativeSnapshot(
        db, boundary: boundary)
      try Self.commitCloudTraversalPageIfPresent(
        db,
        request: CloudTraversalCommitRequest(
          boundary: boundary, traversalIdentifier: traversalIdentifier, page: page))
      try Self.finishAuthoritativeTraversalLocalState(db)
      return report
    }
  }

  public func cancelCloudTraversal(
    boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws {
    try withCloudTraversalWrite { db in
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: boundary.accountIdentifier,
        zoneIdentifier: boundary.zoneIdentifier)
      guard let progress = state.progress else {
        throw CloudTraversalStateError.noActiveTraversal
      }
      guard progress.boundary == boundary,
        progress.traversalIdentifier == traversalIdentifier
      else { throw CloudTraversalStateError.traversalBoundaryMismatch }
      try CloudTraversalWitness.cancel(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier)
    }
  }

  public func resetCloudTraversalAfterInvalidCursor(
    boundary: CloudTraversalBoundary, traversalIdentifier: String,
    requireFullReseed: Bool
  ) throws {
    try withCloudTraversalWrite { db in
      let state = try CloudTraversalWitness.state(
        db, accountIdentifier: boundary.accountIdentifier,
        zoneIdentifier: boundary.zoneIdentifier)
      guard let progress = state.progress else {
        throw CloudTraversalStateError.noActiveTraversal
      }
      guard progress.boundary == boundary,
        progress.traversalIdentifier == traversalIdentifier
      else { throw CloudTraversalStateError.traversalBoundaryMismatch }
      try CloudTraversalWitness.cancel(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier)
      _ = try CloudTraversalWitness.begin(
        db, boundary: boundary, traversalIdentifier: traversalIdentifier,
        start: .baseline)
      try SyncCheckpoints.clear(
        db, key: Self.remoteFetchFailureCheckpointKey)
      try SyncCheckpoints.clear(
        db, key: Self.remoteFetchFailureCountKey)
      guard requireFullReseed else { return }
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }
  }

  static func commitCloudTraversalPageIfPresent(
    _ db: Database, request: CloudTraversalCommitRequest?
  ) throws {
    guard let request else { return }
    let result = try CloudTraversalWitness.commitPage(
      db, boundary: request.boundary,
      traversalIdentifier: request.traversalIdentifier, page: request.page)
    switch result {
    case .baselineCompleted:
      try SyncCheckpoints.set(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: request.boundary.accountIdentifier),
        value: String(request.boundary.generation))
    case .continuationRecorded, .incrementalCompleted:
      break
    case .alreadyRecorded, .alreadyBaselineCompleted, .alreadyIncrementalCompleted:
      // Every service path preflights before page effects. Under the same
      // SQLite write transaction a new page cannot become a replay; accepting
      // this result would commit effects without owning the cursor transition.
      throw CloudTraversalStateError.traversalBoundaryMismatch
    }
    // A successfully committed page is the exact transaction that disproves a
    // standing per-record fetch failure at this cursor. Clearing separately
    // after return creates a post-commit failure window where canonical rows and
    // the cursor advance but the transport reports no committed page.
    try SyncCheckpoints.clear(db, key: remoteFetchFailureCheckpointKey)
    try SyncCheckpoints.clear(db, key: remoteFetchFailureCountKey)
  }

  /// Returns before any page effects for a durable replay. The preflight and
  /// the eventual commit run under the caller's same SQLite write transaction,
  /// so a page cannot transition from new to duplicate between the two checks.
  static func cloudTraversalPageWasAlreadyCommitted(
    _ db: Database, request: CloudTraversalCommitRequest?
  ) throws -> Bool {
    guard let request else { return false }
    let disposition = try CloudTraversalWitness.preflightPage(
      db, boundary: request.boundary,
      traversalIdentifier: request.traversalIdentifier, page: request.page)
    guard disposition != .new else { return false }
    try recordCommittedCloudTraversalDisposition(
      db, request: request, disposition: disposition)
    return true
  }

  private static func recordCommittedCloudTraversalDisposition(
    _ db: Database, request: CloudTraversalCommitRequest,
    disposition: CloudTraversalPageDisposition
  ) throws {
    if case .alreadyBaselineCompleted = disposition {
      try SyncCheckpoints.set(
        db,
        key: SyncCheckpoints.keyEnrolledZoneEpoch(
          accountIdentifier: request.boundary.accountIdentifier),
        value: String(request.boundary.generation))
    }
  }

  private static func validateAuthoritativeTraversalBoundary(
    _ db: Database, sessionToken: String, boundary: CloudTraversalBoundary,
    traversalIdentifier: String
  ) throws -> String {
    guard sessionToken == traversalIdentifier,
      let session = try AuthoritativeSnapshot.activeSession(db),
      session.sessionToken == sessionToken,
      session.boundary == boundary
    else { throw AuthoritativeSnapshotError.sessionBoundaryMismatch }
    let databaseInstanceIdentifier = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    guard session.databaseInstanceId == databaseInstanceIdentifier else {
      throw AuthoritativeSnapshotError.databaseInstanceMismatch
    }
    let state = try CloudTraversalWitness.state(
      db, accountIdentifier: boundary.accountIdentifier,
      zoneIdentifier: boundary.zoneIdentifier)
    guard state.progress?.boundary == boundary,
      state.progress?.traversalIdentifier == traversalIdentifier,
      state.progress?.mode == .baseline,
      state.progress?.startingChangeToken == nil
    else { throw CloudTraversalStateError.traversalBoundaryMismatch }
    return databaseInstanceIdentifier
  }

  private static func finishAuthoritativeTraversalLocalState(_ db: Database) throws {
    try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyReseedRequired)
    try SyncCheckpoints.clear(db, key: remoteFetchFailureCheckpointKey)
    try SyncCheckpoints.clear(db, key: remoteFetchFailureCountKey)
  }

  /// Traversal bookkeeping is not a user-domain mutation, so it must not bump
  /// `local_change_seq`; it still needs the same commit-time managed-storage
  /// identity guard as the normal write funnels so a concurrent factory reset
  /// cannot commit a witness into the unlinked, erased database generation.
  func withCloudTraversalWrite<T>(
    _ body: @Sendable (Database) throws -> T
  ) throws -> T {
    try withStorageCutoverRetry {
      let (deviceId, _) = try writeState()
      Self.afterWriteStateBarrierForTesting?()
      return try write { db in
        try self.assertCommittingDatabaseIdentity(db, expected: deviceId)
        return try body(db)
      }
    }
  }
}
