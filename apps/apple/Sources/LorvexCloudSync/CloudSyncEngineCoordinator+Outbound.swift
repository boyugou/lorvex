@preconcurrency import CloudKit
import LorvexCore
import LorvexDomain
import LorvexSync
import os

struct CloudSyncOutboundReport: Sendable, Equatable {
  var pushed = 0
  var failed = 0
  var moreComing = false
  var inbound = InboundApplyReport()

  mutating func accumulate(_ other: CloudSyncOutboundReport) {
    pushed += other.pushed
    failed += other.failed
    moreComing = other.moreComing
    inbound.accumulate(other.inbound)
  }
}

private struct CloudSyncOutboundPage: Sendable {
  var report = CloudSyncOutboundReport()
  /// Highest FIFO id examined by this page. The next page starts strictly after
  /// it, so a failed row cannot be retried again inside the same drain.
  var lastExaminedOutboxId: Int64?
}

struct CloudSyncOutboundCursorInvariantViolation: Error, LocalizedError, Sendable {
  var errorDescription: String? {
    "CloudSync outbound cursor did not advance."
  }
}

struct CloudSyncPartialOutboundFailure: Error, @unchecked Sendable {
  let partialReport: CloudSyncOutboundReport
  let underlyingError: any Error
}

extension CloudSyncEngineCoordinator {
  /// Covers the complete 100,000-record generation ceiling in the ordinary
  /// no-conflict path, with additional pages for strict successors, while still
  /// stopping a continuously-writing peer from keeping one coordinator
  /// operation alive forever.
  static let maxOutboundDrainIterations = 128

  /// Fixed per-record wire overhead added to each envelope's payload byte count
  /// when estimating its contribution to ``maxPushBatchBytes`` — CKRecord
  /// framing, the identity/version/device wire fields, and encryption padding.
  static let estimatedRecordOverheadBytes = 512

  /// Estimate a record's contribution to a chunk's cumulative byte budget from
  /// its source envelope. Dominated by the (already size-capped) payload; the
  /// identity/version/device fields plus ``estimatedRecordOverheadBytes`` cover
  /// the remaining wire framing. An estimate, not an exact wire size — the hard
  /// backstop for an under-estimate is the pusher's subdivide-on-`limitExceeded`.
  static func estimatedRecordBytes(_ envelope: SyncEnvelope) -> Int {
    envelope.payload.utf8.count
      + envelope.entityType.asString.utf8.count
      + envelope.entityId.utf8.count
      + envelope.version.description.utf8.count
      + envelope.deviceId.utf8.count
      + estimatedRecordOverheadBytes
  }

  /// Drain the outbox to CloudKit, chunking by both record count
  /// (``maxPushBatchSize``) and cumulative estimated bytes (``maxPushBatchBytes``)
  /// so a run of large aggregate payloads cannot form a single over-budget push.
  ///
  /// Each chunk is its own `push` call; per-result confirm/fail bookkeeping is
  /// accumulated across chunks. A per-record failure does not stop later chunks.
  /// A chunk that throws WHOLESALE (a `limitExceeded` the pusher could not
  /// subdivide, or any other push error) is caught locally: every row in the
  /// aborted chunk is recorded as a failure (transient → diagnostics only,
  /// otherwise `.wholesale` — retry_count advances at the linear cap, exempt
  /// from same-error escalation) and the drain continues, so one poison chunk
  /// can neither abort confirmation of the earlier chunks nor re-throw forever
  /// and wedge outbound.
  ///
  /// `outboxScanTimestamp` is fixed for the whole cursor walk. A parked low-id
  /// row that becomes due while later pages are in flight stays parked until the
  /// next drain (and remains visible to the durable wake query), rather than
  /// being globally re-armed behind this drain's advanced cursor and becoming
  /// invisible to both mechanisms.
  func pushOutbound(
    sync: any EnvelopeSyncServicing,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    authorization: AuditRetentionOutboundAuthorization,
    metadata: CloudSyncAuditRetentionMetadata = .initial,
    outboxScanTimestamp: String = SyncTimestampFormat.syncTimestampNow()
  ) async throws -> CloudSyncOutboundReport {
    var aggregate = CloudSyncOutboundReport()
    var cursor: Int64?
    var currentAuthorization = authorization
    var currentMetadata = metadata
    var retentionRefreshAttempts = 0
    var completedPages = 0

    while completedPages < outboundDrainIterationLimit {
      let page: CloudSyncOutboundPage
      do {
        page = try await pushOutboundPage(
          sync: sync, afterOutboxId: cursor, context: context,
          expectation: expectation, authorization: currentAuthorization,
          metadata: currentMetadata, outboxScanTimestamp: outboxScanTimestamp)
      } catch let guardError as CloudSyncAuditRetentionGuardError {
        switch guardError {
        case .missing, .stale:
          guard
            retentionRefreshAttempts + 1
              < CloudKitRecordPusher.maxZoneEpochCASAttempts
          else {
            let error = CloudSyncZoneEpochError.zoneEpochCASRetryLimitExceeded
            guard cursor != nil else { throw error }
            throw CloudSyncPartialOutboundFailure(
              partialReport: aggregate, underlyingError: error)
          }
          retentionRefreshAttempts += 1
          let refreshed: (
            metadata: CloudSyncAuditRetentionMetadata,
            authorization: AuditRetentionOutboundAuthorization
          )
          do {
            refreshed = try await prepareReadyRetention(
              sync: sync, context: context, expectation: expectation,
              boundaryGuard: generationBoundaryGuard(
                accountIdentifier: context.accountIdentifier,
                expectation: expectation))
          } catch {
            guard cursor != nil else { throw error }
            throw CloudSyncPartialOutboundFailure(
              partialReport: aggregate, underlyingError: error)
          }
          currentAuthorization = refreshed.authorization
          currentMetadata = refreshed.metadata
          // Retry this exact page. The cursor is intentionally unchanged, so
          // earlier pages (including their failures) are never attempted twice.
          continue
        case .invalidAtomicResult, .transport:
          guard cursor != nil else { throw guardError }
          throw CloudSyncPartialOutboundFailure(
            partialReport: aggregate, underlyingError: guardError)
        }
      } catch let partial as CloudSyncPartialOutboundFailure {
        throw partial
      } catch {
        guard cursor != nil else { throw error }
        throw CloudSyncPartialOutboundFailure(
          partialReport: aggregate, underlyingError: error)
      }
      retentionRefreshAttempts = 0
      aggregate.accumulate(page.report)
      guard let nextCursor = page.lastExaminedOutboxId else { return aggregate }
      guard cursor.map({ nextCursor > $0 }) ?? true else {
        throw CloudSyncPartialOutboundFailure(
          partialReport: aggregate,
          underlyingError: CloudSyncOutboundCursorInvariantViolation())
      }
      cursor = nextCursor
      completedPages += 1
    }

    // A full final page may still have been the end of the queue. Scan once
    // before reporting a continuation. The scan may defensively park or fence
    // newly discovered bad rows, but it never pushes anything; the cursor keeps
    // every row attempted above out of the result.
    do {
      aggregate.moreComing = try sync.pendingOutboundPage(
        afterOutboxId: cursor, now: outboxScanTimestamp
      ).lastScannedOutboxId != nil
    } catch {
      throw CloudSyncPartialOutboundFailure(
        partialReport: aggregate, underlyingError: error)
    }
    return aggregate
  }

  private func pushOutboundPage(
    sync: any EnvelopeSyncServicing,
    afterOutboxId: Int64?,
    context: CloudSyncGenerationContext,
    expectation: CloudSyncGenerationExpectation,
    authorization: AuditRetentionOutboundAuthorization,
    metadata: CloudSyncAuditRetentionMetadata,
    outboxScanTimestamp: String
  ) async throws -> CloudSyncOutboundPage {
    let boundaryGuard = generationBoundaryGuard(
      accountIdentifier: context.accountIdentifier, expectation: expectation)
    guard await boundaryGuard() else {
      throw CloudSyncGenerationBoundaryCrossed()
    }
    let scanned = try sync.pendingOutboundPage(
      afterOutboxId: afterOutboxId, now: outboxScanTimestamp)
    let pending = scanned.envelopes
    if pending.isEmpty {
      return CloudSyncOutboundPage(lastExaminedOutboxId: scanned.lastScannedOutboxId)
    }
    let lastExaminedOutboxId = scanned.lastScannedOutboxId

    // Map each CK record name back to its outbox row so push results can confirm
    // or fail the exact row; carry a parallel byte estimate for chunk sizing.
    var outboxIdByRecordName: [String: Int64] = [:]
    var envelopeByRecordName: [String: SyncEnvelope] = [:]
    var auditRecords: [CKRecord] = []
    var records: [CKRecord] = []
    var recordBytes: [Int] = []
    auditRecords.reserveCapacity(pending.count)
    records.reserveCapacity(pending.count)
    recordBytes.reserveCapacity(pending.count)
    for item in pending {
      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      if item.envelope.entityType == .aiChangelog {
        let mark = try sync.markAuditCloudPresencePossible(
          outboxId: item.outboxId, authorization: authorization)
        guard await boundaryGuard() else {
          throw CloudSyncGenerationBoundaryCrossed()
        }
        if mark == .noLongerPending { continue }
      }
      let record = CloudSyncEnvelopeRecord.makeRecord(
        item.envelope, zoneID: context.zoneID)
      outboxIdByRecordName[record.recordID.recordName] = item.outboxId
      envelopeByRecordName[record.recordID.recordName] = item.envelope
      if item.envelope.entityType == .aiChangelog {
        auditRecords.append(record)
      } else {
        records.append(record)
        recordBytes.append(Self.estimatedRecordBytes(item.envelope))
      }
    }

    var reportedNames = Set<String>()
    var syncedIds: [Int64] = []
    var failures: [OutboundFailureRecord] = []
    var failedCount = 0
    // Server records returned by lost LWW conflicts (`serverRecordChanged`
    // resolved in the server's favor). The server holds a version this device
    // must also hold; the conflicting record could predate our inbound
    // checkpoint and so be skipped by the same-cycle pull, so it is applied here
    // from the push path. Apply is idempotent (the engine's LWW gate no-ops a
    // record we already have), so this never double-applies.
    var serverEnvelopesToApply: [SyncEnvelope] = []
    // Future server records returned by lost LWW conflicts. These are the push
    // path equivalent of inbound-fetch `.unknownEntityType`: park before any
    // outbox confirmation so a crash cannot lose a forward-compatible winner.
    var serverRawsToDefer: [RawEnvelopeFields] = []
    // Equal-HLC semantic collisions and exact-slot corruption cannot consume
    // the old outbox row. Core re-reads that exact id and authors a strict
    // successor in the same transaction as every other outbound result.
    var collisions: [OutboundCollisionRecord] = []
    // Conflict-returned change tags are intentionally held outside the cache
    // until the matching successor transaction commits.
    var collisionSystemFieldsReceiptByOutboxId:
      [Int64: CloudSyncSystemFieldsReceipt] = [:]
    var cloudReceipts: [OutboundCloudRecordReceipt] = []
    var serverWinnerCloudReceipts: [InboundCloudRecordReceipt] = []

    func consume(_ results: [CloudSyncPushResult]) {
      for result in results {
        reportedNames.insert(result.recordName)
        guard let outboxId = outboxIdByRecordName[result.recordName] else { continue }
        if let collision = result.collision {
          let kind: OutboundCollisionKind
          switch collision {
          case .equalVersion(let serverEnvelope):
            kind = .equalVersion(serverEnvelope: serverEnvelope)
          case .semanticMerge(let semanticKind, let serverEnvelope):
            kind = .semanticMerge(kind: semanticKind, serverEnvelope: serverEnvelope)
          case .entityRedirectDelete(let serverEnvelope):
            kind = .entityRedirectDelete(serverEnvelope: serverEnvelope)
          case .immutableIdentity(let serverEnvelope):
            kind = .immutableIdentity(serverEnvelope: serverEnvelope)
          case .corruptServerSlot(let serverVersionFloor):
            kind = .corruptServerSlot(serverVersionFloor: serverVersionFloor)
          }
          collisions.append(OutboundCollisionRecord(outboxId: outboxId, kind: kind))
          if let receipt = result.systemFieldsReceipt,
            receipt.recordName == result.recordName
          {
            collisionSystemFieldsReceiptByOutboxId[outboxId] = receipt
          }
          continue
        }
        if result.succeeded {
          syncedIds.append(outboxId)
          if let serverEnvelope = result.serverEnvelopeToApply {
            serverEnvelopesToApply.append(serverEnvelope)
          }
          if let date = result.serverModificationDate {
            let timestamp = SyncTimestampFormat.formatSyncTimestamp(date)
            if let serverEnvelope = result.serverEnvelopeToApply {
              serverWinnerCloudReceipts.append(
                Self.inboundCloudReceipt(
                  envelope: serverEnvelope, serverModifiedAt: date))
              cloudReceipts.append(
                OutboundCloudRecordReceipt(
                  outboxId: outboxId, serverModifiedAt: timestamp))
            } else if let local = envelopeByRecordName[result.recordName] {
              let receipt = Self.inboundCloudReceipt(
                envelope: local, serverModifiedAt: date)
              cloudReceipts.append(
                OutboundCloudRecordReceipt(
                  outboxId: outboxId, serverModifiedAt: timestamp,
                  tombstoneConfirmation: receipt.tombstoneConfirmation))
            }
          }
        } else {
          if let serverRaw = result.serverRawToDefer {
            serverRawsToDefer.append(serverRaw)
          }
          failedCount += 1
          failures.append(
            OutboundFailureRecord(
              outboxId: outboxId,
              error: result.errorMessage ?? "CloudKit push failed",
              kind: result.isTransient ? .transient : .perRecord))
        }
      }
    }

    // Audit goes first. A stale metadata guard aborts before any unrelated
    // business record leaves the device, so the caller can merge the new
    // frontier, prune dominated audit rows, and retry with a fresh capability.
    if !auditRecords.isEmpty {
      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      do {
        consume(
          try await pusher.pushAuditRecords(
            auditRecords, guardedBy: metadata, context: context,
            expectation: expectation, boundaryGuard: boundaryGuard))
      } catch let guardError as CloudSyncAuditRetentionGuardError {
        throw guardError
      } catch is CloudSyncGenerationBoundaryCrossed {
        throw CloudSyncGenerationBoundaryCrossed()
      } catch is CloudSyncAccountBoundaryCrossed {
        throw CloudSyncAccountBoundaryCrossed()
      } catch {
        let transient = CloudSyncTransientClassifier.isTransient(error)
        for record in auditRecords {
          let name = record.recordID.recordName
          reportedNames.insert(name)
          guard let outboxId = outboxIdByRecordName[name] else { continue }
          failedCount += 1
          failures.append(
            OutboundFailureRecord(
              outboxId: outboxId,
              error: "guarded audit push failed: \(error.localizedDescription)",
              kind: transient ? .transient : .wholesale))
        }
      }
    }

    var chunkStart = 0
    while chunkStart < records.count {
      // Re-check the account boundary before each chunk, so a switch between
      // chunks is caught before any of the chunk's rows ship — and even for a
      // pusher fake that does not itself honor the guard. The pusher re-checks
      // again before every individual request inside `push`.
      guard await boundaryGuard() else {
        throw CloudSyncGenerationBoundaryCrossed()
      }
      var chunkEnd = chunkStart
      var chunkBytes = 0
      while chunkEnd < records.count {
        // Always admit the first record even if it alone exceeds the byte budget;
        // an un-splittable oversized record is failed by the pusher, not thrown.
        if chunkEnd > chunkStart {
          if chunkEnd - chunkStart >= Self.maxPushBatchSize { break }
          if chunkBytes + recordBytes[chunkEnd] > Self.maxPushBatchBytes { break }
        }
        chunkBytes += recordBytes[chunkEnd]
        chunkEnd += 1
      }
      let chunk = Array(records[chunkStart..<chunkEnd])
      chunkStart = chunkEnd

      let results: [CloudSyncPushResult]
      do {
        results = try await pusher.push(
          chunk, context: context, expectation: expectation,
          boundaryGuard: boundaryGuard)
      } catch is CloudSyncGenerationBoundaryCrossed {
        throw CloudSyncGenerationBoundaryCrossed()
      } catch is CloudSyncAccountBoundaryCrossed {
        // The account switched WHILE this chunk was mid-request. No collected
        // result is locally consumed: every row stays pending and unfailed for
        // an idempotent retry if this account becomes active again.
        throw CloudSyncAccountBoundaryCrossed()
      } catch {
        // A wholesale chunk throw (network down / rate limit / outage) records the
        // SAME stable error string on EVERY row in the chunk. Classify it once: a
        // transient outage must not advance any row toward retry wait, or offline
        // editing would pause the whole outbox within a few cycles (SY2). A
        // non-transient chunk throw is still no evidence about any particular
        // row, so it is reported `.wholesale` — retry_count advances (a poison
        // chunk still enters delayed retry wait at the linear cap) without the
        // same-error fast-forward that would pause the whole backlog in three cycles.
        let transient = CloudSyncTransientClassifier.isTransient(error)
        for record in chunk {
          let name = record.recordID.recordName
          reportedNames.insert(name)
          guard let outboxId = outboxIdByRecordName[name] else { continue }
          failedCount += 1
          failures.append(
            OutboundFailureRecord(
              outboxId: outboxId,
              error: "push chunk failed: \(error.localizedDescription)",
              kind: transient ? .transient : .wholesale))
        }
        continue
      }

      consume(results)
    }

    guard await boundaryGuard() else {
      // A generation transition after the transport returned makes every result
      // stale. Leave all rows pending and do not apply/cache/confirm/fail them.
      throw CloudSyncGenerationBoundaryCrossed()
    }

    // Rows with no reported result remain unconfirmed and receive wholesale
    // ambiguity bookkeeping for the next pass.
    // `.wholesale`: a withheld result is chunk-level ambiguity, not per-record
    // evidence, so it advances retry_count without the same-error escalation.
    // A boundary crossing throws before reaching here, so withheld-result
    // accounting can never charge rows for an account/generation transition.
    for (recordName, outboxId) in outboxIdByRecordName where !reportedNames.contains(recordName) {
      failedCount += 1
      failures.append(
        OutboundFailureRecord(
          outboxId: outboxId, error: "no push result returned", kind: .wholesale))
    }

    // One local commit point after the final boundary validation above. If
    // winner apply, future-record parking, any retry update, or confirmation
    // fails, SQLite rolls every one of them back and no apply report is lost.
    let reconciliation = try sync.reconcileOutbound(
      OutboundReconciliationRequest(
        accountIdentifier: context.accountIdentifier,
        serverWinnerEnvelopes: serverEnvelopesToApply,
        deferredUnknownTypeRecords: serverRawsToDefer,
        collisions: collisions,
        failures: failures,
        confirmedOutboxIds: syncedIds,
        cloudReceipts: cloudReceipts,
        serverWinnerCloudReceipts: serverWinnerCloudReceipts))
    // The local successor now exists durably. It is finally safe to retain the
    // server's current change tag: the next push carries that tag together with
    // the strict successor, never with the collided old mutation. A cache-write
    // failure leaves the successor pending and merely forces another conflict.
    let safeReceipts = reconciliation.reconciledCollisionOutboxIds.compactMap {
      collisionSystemFieldsReceiptByOutboxId[$0]
    }
    do {
      try await pusher.commitReconciledConflictSystemFields(
        safeReceipts, context: context, expectation: expectation,
        boundaryGuard: boundaryGuard)
    } catch {
      // The canonical reconciliation and outbox disposition are already one
      // committed SQLite transaction. This reconstructible cache only avoids a
      // later conflict round trip; it must never erase that committed report.
      Self.log.error(
        "CloudSync could not cache reconciled record system fields: \(error.localizedDescription, privacy: .private)")
    }
    return CloudSyncOutboundPage(
      report: CloudSyncOutboundReport(
        pushed: syncedIds.count, failed: failedCount, inbound: reconciliation.inbound),
      lastExaminedOutboxId: lastExaminedOutboxId)
  }
}
