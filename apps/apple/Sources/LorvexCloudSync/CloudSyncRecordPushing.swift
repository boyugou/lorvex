import Foundation
import LorvexCore
import LorvexDomain
import LorvexSync
@preconcurrency import CloudKit

/// Defense-in-depth refusal for a locally constructed record whose HLC cannot
/// be accepted by any conforming peer under the shared operational wire limit.
public struct CloudSyncOperationalWireCeilingExceeded: Error, Sendable, Equatable {}

/// Production `CloudSyncRecordPushing` over a private `CKDatabase`.
public actor CloudKitRecordPusher: CloudSyncRecordPushing {
  /// Bound on the local-wins re-save retry loop for a single record. Each
  /// re-save re-stamps the local payload onto the latest server record and can
  /// itself lose to a concurrent write, surfacing a fresh `serverRecordChanged`;
  /// the bound stops a pathological write-storm from looping a contested record
  /// forever within one push call. A record that exhausts the budget is left
  /// failed for the next cycle.
  public static let maxLocalWinsResaveAttempts = 3
  /// Bounded retry budget for the singleton zone-epoch CAS. Contention is rare,
  /// but every lost change-tag race must refetch before choosing a generation.
  public static let maxZoneEpochCASAttempts = 16
  /// A device may take over a rebuilding lease only after its server-assigned
  /// modification time has been idle this long. Until then, fail closed rather
  /// than letting two devices destructively rebuild the same generation.
  public static let zoneRebuildTakeoverInterval: TimeInterval = 24 * 60 * 60

  let database: any CloudKitDatabaseModifying
  let systemFieldsStore: any CloudSyncRecordSystemFieldsStoring
  let serverClock: any CloudKitServerClockCommitting

  public init(
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier,
    systemFieldsStore: any CloudSyncRecordSystemFieldsStoring =
      InMemoryCloudSyncRecordSystemFieldsStore()
  ) {
    let database = LiveCloudKitDatabase(containerIdentifier: containerIdentifier)
    self.database = database
    self.systemFieldsStore = systemFieldsStore
    self.serverClock = CloudKitServerClockCommitter(database: database)
  }

  /// Test seam: inject a fake ``CloudKitDatabaseModifying`` to drive `push`
  /// without CloudKit.
  init(
    database: any CloudKitDatabaseModifying,
    systemFieldsStore: any CloudSyncRecordSystemFieldsStoring,
    serverClock: any CloudKitServerClockCommitting
  ) {
    self.database = database
    self.systemFieldsStore = systemFieldsStore
    self.serverClock = serverClock
  }

  public func push(
    _ records: [CKRecord], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    if records.isEmpty { return [] }
    guard records.allSatisfy(Self.hasOperationalWireVersion) else {
      throw CloudSyncOperationalWireCeilingExceeded()
    }
    guard context.matches(expectation),
      records.allSatisfy({ $0.recordID.zoneID == context.zoneID })
    else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    return try await pushWithinRequestLimit(
      prepareForPush(records, context: context), context: context,
      expectation: expectation, boundaryGuard: boundaryGuard)
  }

  static func hasOperationalWireVersion(_ record: CKRecord) -> Bool {
    switch CloudSyncEnvelopeRecord.decode(record) {
    case .decoded(let envelope):
      return Hlc.isOperationallyAcceptableWire(envelope.version)
    case .unknownEntityType(let raw):
      guard let version = try? Hlc.parseCanonical(raw.version) else { return false }
      return Hlc.isOperationallyAcceptableWire(version)
    case .foreign, .corrupt:
      // Existing structural validation and result mapping own these cases. This
      // guard is deliberately only the operational-HLC defense.
      return true
    }
  }

  /// Re-hydrate each outgoing record from its cached CKRecord system fields when
  /// available, so a record already saved to the server carries its current
  /// change tag and satisfies `.ifServerRecordUnchanged` on the first try (SY10).
  /// A record with no cache entry (never pushed, or the cache was lost) is sent
  /// as-is and takes the one-time conflict path, which re-caches the tag.
  func prepareForPush(
    _ records: [CKRecord], context: CloudSyncGenerationContext
  ) async -> [CKRecord] {
    var prepared: [CKRecord] = []
    prepared.reserveCapacity(records.count)
    for record in records {
      if let hydrated = await recordCarryingCachedSystemFields(record, context: context) {
        prepared.append(hydrated)
      } else {
        prepared.append(record)
      }
    }
    return prepared
  }

  /// Reconstruct a CKRecord from the cached system fields for `record`'s name
  /// (carrying the server's change tag) and re-stamp `record`'s wire fields onto
  /// it. Returns `nil` when nothing is cached or the archive is undecodable, so
  /// the caller falls back to the freshly built record.
  private func recordCarryingCachedSystemFields(
    _ record: CKRecord, context: CloudSyncGenerationContext
  ) async -> CKRecord? {
    guard
      let data = await systemFieldsStore.systemFields(
        accountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName,
        recordName: record.recordID.recordName),
      let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
    else { return nil }
    unarchiver.requiresSecureCoding = true
    let base = CKRecord(coder: unarchiver)
    unarchiver.finishDecoding()
    guard let base, base.recordType == record.recordType, base.recordID.zoneID == context.zoneID,
      base.recordID.recordName == record.recordID.recordName
    else {
      await systemFieldsStore.remove(
        accountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName,
        recordName: record.recordID.recordName)
      return nil
    }
    CloudSyncEnvelopeRecord.restamp(from: record, onto: base)
    return base
  }

  /// Archive `record`'s CKRecord system fields (recordID + the server-assigned
  /// change tag) into the cache so the next push of this record name matches
  /// `.ifServerRecordUnchanged` without a conflict round trip.
  func cacheSystemFields(
    of record: CKRecord, context: CloudSyncGenerationContext
  ) async {
    guard record.recordID.zoneID == context.zoneID else { return }
    let data = archiveSystemFields(of: record)
    await systemFieldsStore.store(
      data,
      accountIdentifier: context.accountIdentifier,
      zoneName: context.zoneName,
      recordName: record.recordID.recordName)
  }

  private func archiveSystemFields(of record: CKRecord) -> Data {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return archiver.encodedData
  }

  func reconciliationReceipt(
    for record: CKRecord
  ) -> CloudSyncSystemFieldsReceipt {
    CloudSyncSystemFieldsReceipt(
      recordName: record.recordID.recordName,
      archivedSystemFields: archiveSystemFields(of: record))
  }

  public func commitReconciledConflictSystemFields(
    _ receipts: [CloudSyncSystemFieldsReceipt], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    if receipts.isEmpty { return }
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    for receipt in receipts {
      guard
        let unarchiver = try? NSKeyedUnarchiver(
          forReadingFrom: receipt.archivedSystemFields)
      else { continue }
      unarchiver.requiresSecureCoding = true
      let record = CKRecord(coder: unarchiver)
      unarchiver.finishDecoding()
      guard let record, record.recordType == CloudSyncEnvelopeRecord.recordType,
        record.recordID.zoneID == context.zoneID,
        record.recordID.recordName == receipt.recordName
      else { continue }
      await systemFieldsStore.store(
        receipt.archivedSystemFields,
        accountIdentifier: context.accountIdentifier,
        zoneName: context.zoneName,
        recordName: receipt.recordName)
    }
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
  }

  /// Save `records`, recovering from a wholesale `limitExceeded` rejection by
  /// halving the batch. An un-splittable single record returns a failed result so
  /// it advances toward delayed retry wait without blocking unrelated outbound rows.
  private func pushWithinRequestLimit(
    _ records: [CKRecord], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    do {
      return try await modifyAndResolve(
        records, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
    } catch let ckError as CKError where ckError.code == .limitExceeded {
      guard records.count > 1 else {
        let recordName = records.first?.recordID.recordName ?? ""
        return [
          CloudSyncPushResult(
            recordName: recordName, succeeded: false,
            errorMessage:
              "record exceeds CloudKit's per-request size limit and cannot be split: "
              + ckError.localizedDescription)
        ]
      }
      // The head/tail both re-enter `modifyAndResolve`, whose per-request boundary
      // check re-runs the guard before each sub-request — so the account-boundary
      // guard covers every request of the subdivision without extra plumbing. A
      // boundary crossed between the head and tail throws
      // ``CloudSyncAccountBoundaryCrossed`` (not a `CKError`), so it bypasses this
      // `limitExceeded` catch and unwinds the whole push; the head's partial
      // successes are simply not returned and re-push idempotently later.
      let mid = records.count / 2
      let head = try await pushWithinRequestLimit(
        Array(records[..<mid]), context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      let tail = try await pushWithinRequestLimit(
        Array(records[mid...]), context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
      return head + tail
    }
  }

  /// Submit one modify request and map each per-record result into a
  /// ``CloudSyncPushResult``. A `limitExceeded` thrown by the request itself
  /// propagates to ``pushWithinRequestLimit`` for subdivision.
  ///
  /// `.ifServerRecordUnchanged` makes CloudKit's change tag a write barrier;
  /// HLC resolution below is the conflict authority. Non-atomic mode keeps one
  /// rejected entity from turning the whole batch into `batchRequestFailed`.
  private func modifyAndResolve(
    _ records: [CKRecord], context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> [CloudSyncPushResult] {
    // Re-check the account boundary immediately before the write. Because both the
    // `limitExceeded` subdivision and the local-wins re-save funnel through a
    // `modifyRecords`, guarding right here (and in `resaveLocalWinsOntoServer`)
    // covers every external mutation this push performs.
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    let (saveResults, _) = try await database.modifyRecords(
      saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
    // Do not inspect results, cache change tags, or return confirmation after a
    // generation transition. The request may have landed in the now-retired
    // zone, but local outbox state must remain pending for the new generation.
    try await assertRequestBoundary(
      context: context, expectation: expectation, boundaryGuard: boundaryGuard)
    var results: [CloudSyncPushResult] = []
    results.reserveCapacity(saveResults.count)
    for (recordID, result) in saveResults {
      switch result {
      case .success(let savedRecord):
        await cacheSystemFields(of: savedRecord, context: context)
        results.append(
          CloudSyncPushResult(
            recordName: recordID.recordName, succeeded: true,
            serverModificationDate: savedRecord.modificationDate))
      case .failure(let error):
        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
          results.append(
            try await resolveServerRecordChanged(
              error: ckError, recordID: recordID, context: context,
              expectation: expectation, boundaryGuard: boundaryGuard))
        } else if let ckError = error as? CKError, ckError.code == .unknownItem {
          // Stale system fields from an adopted/purged zone: clear the tag so
          // the next retry creates fresh, and keep that retry transient.
          await systemFieldsStore.remove(
            accountIdentifier: context.accountIdentifier,
            zoneName: context.zoneName,
            recordName: recordID.recordName)
          results.append(
            CloudSyncPushResult(
              recordName: recordID.recordName, succeeded: false,
              errorMessage:
                "record unknown in zone; cleared stale system-fields cache for a fresh retry: "
                + ckError.localizedDescription,
              isTransient: true))
        } else {
          results.append(
            CloudSyncPushResult(
              recordName: recordID.recordName, succeeded: false,
              errorMessage: error.localizedDescription,
              isTransient: CloudSyncTransientClassifier.isTransient(error)))
        }
      }
    }
    return results
  }

  /// Resolve one `serverRecordChanged` rejection. Ordinary whole-row entities
  /// use HLC last-writer-wins; fully-known base calendar events instead return a
  /// typed collision for the core's transactional content/topology-register
  /// join. Local whole-row wins re-stamp and re-save with the server change tag;
  /// server wins return a decoded envelope for local apply, reclaim corrupt
  /// records, and wait transiently on honest forward-compat records.
  private func resolveServerRecordChanged(
    error: CKError, recordID: CKRecord.ID, context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncPushResult {
    let recordName = recordID.recordName
    guard
      let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
      let clientRecord = error.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord
    else {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage: "serverRecordChanged without a resolvable server/client record")
    }
    guard serverRecord.recordType == CloudSyncEnvelopeRecord.recordType,
      clientRecord.recordType == CloudSyncEnvelopeRecord.recordType,
      serverRecord.recordID == recordID, clientRecord.recordID == recordID
    else {
      // A different record type cannot be converted in place: CKRecord's type
      // is immutable. Never report success after stamping Lorvex fields onto a
      // foreign record that merely squats the same opaque record name.
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage: "serverRecordChanged returned a foreign or mismatched record slot")
    }
    guard CloudSyncEnvelopeRecord.hasIdenticalEnvelopeIdentity(clientRecord, serverRecord) else {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage: "serverRecordChanged returned a foreign embedded entity identity")
    }
    guard
      let localVersion = CloudSyncEnvelopeRecord.versionString(from: clientRecord),
      (try? Hlc.parseCanonical(localVersion)) != nil
    else {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage: "serverRecordChanged returned an invalid client version")
    }
    let serverVersion = CloudSyncEnvelopeRecord.versionString(from: serverRecord) ?? ""

    if let invalid = try invalidKnownPayloadConflictResult(
      serverRecord: serverRecord, recordName: recordName)
    { return invalid }

    // A schema-ahead operation on an otherwise-known identity is deliberately
    // represented as a raw future record. An older client cannot infer whether
    // its locally newer HLC is allowed to replace that operation, so park and
    // fence it before the outer LWW comparison. Waiting only in the server-wins
    // branch would let a local clock advantage destroy future-authored state.
    if let future = futureRecordConflictResult(
      serverRecord: serverRecord, recordName: recordName)
    { return future }

    // Some current-schema entities are typed joins rather than whole-row LWW,
    // and any schema-ahead server value must be preserved before an older build
    // can overwrite its unknown fields. Route both classes before consulting the
    // outer transport HLC. The retry loop below calls this same classifier after
    // every fresh server movement.
    if case .decoded(let clientEnvelope) = CloudSyncEnvelopeRecord.decode(clientRecord),
      case .decoded(let serverEnvelope) = CloudSyncEnvelopeRecord.decode(serverRecord)
    {
      do {
        if let result = try await semanticConflictResult(
          clientEnvelope: clientEnvelope, serverEnvelope: serverEnvelope,
          serverRecord: serverRecord, recordName: recordName, context: context)
        {
          return result
        }
      } catch {
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage: "semantic conflict classification failed: \(error)")
      }
    }

    switch resolveCloudSyncPushConflict(localVersion: localVersion, serverVersion: serverVersion) {
    case .equalConfirm:
      switch (CloudSyncEnvelopeRecord.decode(clientRecord), CloudSyncEnvelopeRecord.decode(serverRecord)) {
      case (.decoded(let clientEnvelope), .decoded(let serverEnvelope)):
        do {
          if try SyncMutationSemantics.isExactSemanticReplay(clientEnvelope, serverEnvelope) {
            await cacheSystemFields(of: serverRecord, context: context)
            return CloudSyncPushResult(
              recordName: recordName, succeeded: true,
              serverModificationDate: serverRecord.modificationDate)
          }
        } catch {
          return CloudSyncPushResult(
            recordName: recordName, succeeded: false,
            errorMessage: "equal-version semantic comparison failed: \(error)")
        }
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          collision: .equalVersion(serverEnvelope: serverEnvelope),
          systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
      case (_, .unknownEntityType(let raw)):
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage:
            "equal-version conflict returned a forward-compatible mutation this build cannot apply",
          isTransient: true, serverRawToDefer: raw)
      case (_, .corrupt):
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          collision: .corruptServerSlot(
            serverVersionFloor: try? Hlc.parseCanonical(serverVersion)),
          systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
      case (_, .foreign):
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage: "equal-version conflict returned a foreign server record")
      case (.corrupt, _), (.foreign, _), (.unknownEntityType, _):
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage: "equal-version conflict returned an invalid client record")
      }

    case .serverWinsConfirmAndApply:
      // Confirm only when the server record decodes; route undecodable outcomes
      // by type instead of treating all of them as non-transient failures.
      switch CloudSyncEnvelopeRecord.decode(serverRecord) {
      case .decoded(let serverEnvelope):
        // Do not cache the server tag before the later apply/confirm transaction:
        // a crash in that window must re-conflict, not overwrite with local old.
        return CloudSyncPushResult(
          recordName: recordName, succeeded: true, serverEnvelopeToApply: serverEnvelope,
          serverModificationDate: serverRecord.modificationDate)

      case .corrupt:
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          collision: .corruptServerSlot(
            serverVersionFloor: try? Hlc.parseCanonical(serverVersion)),
          systemFieldsReceipt: reconciliationReceipt(for: serverRecord))

      case .unknownEntityType(let raw):
        // Honest forward-compat from a newer build: wait without spending retry budget.
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage:
            "server-wins conflict returned a forward-compat server record this build cannot "
            + "apply yet; waiting for a build that understands it",
          isTransient: true, serverRawToDefer: raw)

      case .foreign:
        // Never overwrite a foreign record squatting our record name.
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false,
          errorMessage: "server-wins conflict returned a foreign server record")
      }

    case .localWinsResaveOntoServer:
      return try await resaveLocalWinsOntoServer(
        clientRecord: clientRecord, serverRecord: serverRecord, recordName: recordName,
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)

    case .corruptServerSlot:
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        collision: .corruptServerSlot(serverVersionFloor: nil),
        systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
    }
  }

  /// Re-stamp the client fields onto the server record carrying the live change
  /// tag, retrying bounded local-wins conflicts and abandoning the re-save as
  /// soon as the server becomes equal/newer.
  private func resaveLocalWinsOntoServer(
    clientRecord: CKRecord, serverRecord: CKRecord, recordName: String,
    context: CloudSyncGenerationContext, expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws -> CloudSyncPushResult {
    var target = serverRecord
    guard
      let localVersion = CloudSyncEnvelopeRecord.versionString(from: clientRecord),
      (try? Hlc.parseCanonical(localVersion)) != nil,
      case .decoded(let clientEnvelope) = CloudSyncEnvelopeRecord.decode(clientRecord)
    else {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage: "local-wins re-save received an invalid client record")
    }

    for _ in 0..<Self.maxLocalWinsResaveAttempts {
      CloudSyncEnvelopeRecord.restamp(from: clientRecord, onto: target)
      // Re-check the account boundary before each re-save attempt, OUTSIDE the
      // `do` below so a crossed boundary throws out of the whole push (leaving the
      // row pending to re-push later) rather than being caught and mapped to a
      // per-record failure that would advance the row toward retry wait.
      try await assertRequestBoundary(
        context: context, expectation: expectation, boundaryGuard: boundaryGuard)
      do {
        let (saveResults, _) = try await database.modifyRecords(
          saving: [target], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        try await assertRequestBoundary(
          context: context, expectation: expectation, boundaryGuard: boundaryGuard)
        guard let result = saveResults[target.recordID] else {
          return CloudSyncPushResult(
            recordName: recordName, succeeded: false,
            errorMessage: "local-wins re-save returned no result")
        }
        switch result {
        case .success(let savedRecord):
          await cacheSystemFields(of: savedRecord, context: context)
          return CloudSyncPushResult(
            recordName: recordName, succeeded: true,
            serverModificationDate: savedRecord.modificationDate)
        case .failure(let error):
          guard let ckError = error as? CKError, ckError.code == .serverRecordChanged,
            let freshServer = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord,
            freshServer.recordType == CloudSyncEnvelopeRecord.recordType,
            freshServer.recordID == clientRecord.recordID
          else {
            return CloudSyncPushResult(
              recordName: recordName, succeeded: false,
              errorMessage: error.localizedDescription)
          }
          guard CloudSyncEnvelopeRecord.hasIdenticalEnvelopeIdentity(clientRecord, freshServer)
          else {
            return CloudSyncPushResult(
              recordName: recordName, succeeded: false,
              errorMessage: "local-wins retry returned a foreign embedded entity identity")
          }
          if let invalid = try invalidKnownPayloadConflictResult(
            serverRecord: freshServer, recordName: recordName)
          { return invalid }
          if let future = futureRecordConflictResult(
            serverRecord: freshServer, recordName: recordName)
          { return future }
          // Repeat the complete semantic/future classifier because the slot can
          // move to a different contender between bounded attempts.
          if case .decoded(let freshServerEnvelope) =
            CloudSyncEnvelopeRecord.decode(freshServer)
          {
            do {
              if let result = try await semanticConflictResult(
                clientEnvelope: clientEnvelope, serverEnvelope: freshServerEnvelope,
                serverRecord: freshServer, recordName: recordName, context: context)
              {
                return result
              }
            } catch {
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage: "semantic conflict retry classification failed: \(error)")
            }
          }
          let freshServerVersion =
            CloudSyncEnvelopeRecord.versionString(from: freshServer) ?? ""
          // The server moved again under us. Re-resolve against the new server
          // version: only keep retrying while local strictly wins; otherwise the
          // server now wins and we apply its record instead of overwriting it.
          switch resolveCloudSyncPushConflict(
            localVersion: localVersion, serverVersion: freshServerVersion)
          {
          case .localWinsResaveOntoServer:
            target = freshServer
            continue
          case .equalConfirm:
            switch CloudSyncEnvelopeRecord.decode(freshServer) {
            case .decoded(let serverEnvelope):
              do {
                if try SyncMutationSemantics.isExactSemanticReplay(
                  clientEnvelope, serverEnvelope)
                {
                  await cacheSystemFields(of: freshServer, context: context)
              return CloudSyncPushResult(
                recordName: recordName, succeeded: true,
                serverModificationDate: freshServer.modificationDate)
                }
              } catch {
                return CloudSyncPushResult(
                  recordName: recordName, succeeded: false,
                  errorMessage: "equal-version semantic comparison failed: \(error)")
              }
              // Equal ordering keys with different semantics have no LWW winner.
              // Never keep re-saving either contender under that same key: core
              // performs a deterministic join and authors one strict successor.
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                collision: .equalVersion(serverEnvelope: serverEnvelope),
                systemFieldsReceipt: reconciliationReceipt(for: freshServer))
            case .unknownEntityType(let raw):
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage:
                  "equal-version conflict returned a forward-compatible mutation this build "
                  + "cannot apply",
                isTransient: true, serverRawToDefer: raw)
            case .corrupt:
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                collision: .corruptServerSlot(
                  serverVersionFloor: try? Hlc.parseCanonical(freshServerVersion)),
                systemFieldsReceipt: reconciliationReceipt(for: freshServer))
            case .foreign:
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage: "equal-version conflict returned a foreign server record")
            }
          case .serverWinsConfirmAndApply:
            // Same undecodable-outcome routing as `resolveServerRecordChanged`.
            switch CloudSyncEnvelopeRecord.decode(freshServer) {
            case .decoded(let serverEnvelope):
              // Do not cache before the later apply/confirm transaction; retry
              // must re-conflict rather than overwrite with local old.
              return CloudSyncPushResult(
                recordName: recordName, succeeded: true,
                serverEnvelopeToApply: serverEnvelope,
                serverModificationDate: freshServer.modificationDate)
            case .corrupt:
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                collision: .corruptServerSlot(
                  serverVersionFloor: try? Hlc.parseCanonical(freshServerVersion)),
                systemFieldsReceipt: reconciliationReceipt(for: freshServer))
            case .unknownEntityType(let raw):
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage:
                  "server-wins conflict returned a forward-compat server record this build cannot "
                  + "apply yet; waiting for a build that understands it",
                isTransient: true, serverRawToDefer: raw)
            case .foreign:
              return CloudSyncPushResult(
                recordName: recordName, succeeded: false,
                errorMessage: "server-wins conflict returned a foreign server record")
            }
          case .corruptServerSlot:
            return CloudSyncPushResult(
              recordName: recordName, succeeded: false,
              collision: .corruptServerSlot(serverVersionFloor: nil),
              systemFieldsReceipt: reconciliationReceipt(for: freshServer))
          }
        }
      } catch let error as SyncPayloadTransportValidationError {
        throw error
      } catch is CloudSyncAccountBoundaryCrossed {
        throw CloudSyncAccountBoundaryCrossed()
      } catch is CloudSyncGenerationBoundaryCrossed {
        throw CloudSyncGenerationBoundaryCrossed()
      } catch {
        return CloudSyncPushResult(
          recordName: recordName, succeeded: false, errorMessage: error.localizedDescription)
      }
    }
    return CloudSyncPushResult(
      recordName: recordName, succeeded: false,
      errorMessage: "local-wins re-save exhausted \(Self.maxLocalWinsResaveAttempts) attempts")
  }

  /// Intercept every conflict that cannot safely use the envelope's outer HLC.
  /// Exact replays remain ordinary confirmations. A schema-ahead server record
  /// is parked verbatim and fences the local intent; current-schema typed joins
  /// are returned to Core with the server change-tag receipt still uncommitted.
  private func semanticConflictResult(
    clientEnvelope: SyncEnvelope, serverEnvelope: SyncEnvelope,
    serverRecord: CKRecord, recordName: String,
    context: CloudSyncGenerationContext
  ) async throws -> CloudSyncPushResult? {
    if try SyncMutationSemantics.isExactSemanticReplay(clientEnvelope, serverEnvelope) {
      await cacheSystemFields(of: serverRecord, context: context)
      return CloudSyncPushResult(
        recordName: recordName, succeeded: true,
        serverModificationDate: serverRecord.modificationDate)
    }

    if serverEnvelope.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        errorMessage:
          "server conflict carries a future payload schema; waiting for a build that understands it",
        isTransient: true,
        serverRawToDefer: RawEnvelopeFields(
          entityType: serverEnvelope.entityType.asString,
          entityId: serverEnvelope.entityId,
          operation: serverEnvelope.operation.asString,
          version: serverEnvelope.version.description,
          payloadSchemaVersion: serverEnvelope.payloadSchemaVersion,
          payload: serverEnvelope.payload,
          deviceId: serverEnvelope.deviceId))
    }

    if clientEnvelope.entityType == .entityRedirect,
      clientEnvelope.operation == .upsert,
      serverEnvelope.entityType == .entityRedirect,
      serverEnvelope.operation == .delete
    {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        collision: .entityRedirectDelete(serverEnvelope: serverEnvelope),
        systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
    }

    guard let kind = try SemanticPushConflictRouting.classify(
      client: clientEnvelope, server: serverEnvelope)
    else { return nil }
    return CloudSyncPushResult(
      recordName: recordName, succeeded: false,
      collision: .semanticMerge(kind: kind, serverEnvelope: serverEnvelope),
      systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
  }

  private func futureRecordConflictResult(
    serverRecord: CKRecord, recordName: String
  ) -> CloudSyncPushResult? {
    guard case .unknownEntityType(let raw) = CloudSyncEnvelopeRecord.decode(serverRecord)
    else { return nil }
    return CloudSyncPushResult(
      recordName: recordName, succeeded: false,
      errorMessage:
        "server conflict carries a forward-compatible mutation; waiting for a build that understands it",
      isTransient: true, serverRawToDefer: raw)
  }

  /// A CKRecord may satisfy the structural envelope decoder while violating
  /// the immutable payload manifest (missing required fields, invalid register
  /// shapes, or an invalid current floor under a future schema). Such a record
  /// is corrupt, not a server winner or honest forward-compatible hold. Route it
  /// to Core's strict-successor repair while retaining the canonical server HLC
  /// as a floor. Contract-resource failures throw and fail locally instead.
  private func invalidKnownPayloadConflictResult(
    serverRecord: CKRecord, recordName: String
  ) throws -> CloudSyncPushResult? {
    guard case .decoded(let serverEnvelope) = CloudSyncEnvelopeRecord.decode(serverRecord)
    else { return nil }
    let violations = try SyncPayloadTransportValidation.violations(for: serverEnvelope)
    guard !violations.isEmpty else { return nil }
    // A redirect Delete is a known permanent-invariant violation, not an
    // arbitrary malformed payload. Preserve that typed distinction so Core can
    // re-author the canonical alias with a strict successor. It is still never
    // accepted or applied as a valid server winner.
    if serverEnvelope.entityType == .entityRedirect,
      serverEnvelope.operation == .delete
    {
      return CloudSyncPushResult(
        recordName: recordName, succeeded: false,
        collision: .entityRedirectDelete(serverEnvelope: serverEnvelope),
        systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
    }
    return CloudSyncPushResult(
      recordName: recordName, succeeded: false,
      collision: .corruptServerSlot(serverVersionFloor: serverEnvelope.version),
      systemFieldsReceipt: reconciliationReceipt(for: serverRecord))
  }

  /// Exact pre/post request fence shared by ordinary entity mutations. Account
  /// identity and the default-zone generation descriptor are independent
  /// authorities; both must still match before a request and before any result
  /// is allowed to affect local state.
  func assertRequestBoundary(
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    boundaryGuard: (@Sendable () async -> Bool)?
  ) async throws {
    guard context.matches(expectation) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    guard await boundaryGuard?() ?? true else {
      throw CloudSyncAccountBoundaryCrossed()
    }
    let state = try await currentZoneGenerationState()
    guard expectation.matches(state) else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    guard await boundaryGuard?() ?? true else {
      throw CloudSyncAccountBoundaryCrossed()
    }
  }
}
