import CloudKit
import Foundation
import LorvexCloudSync
import LorvexSync
import Testing

@testable import LorvexCore

/// SY2 regression: an iCloud-storage-full (`quotaExceeded`) or ambiguous-outcome
/// (`serverResponseLost`) push failure is a TRANSIENT outage — it clears when the
/// user frees space or the network recovers — so it must never advance an outbox
/// row toward delayed retry wait.
///
/// Before the classifier covered these codes, a storage-full outage recorded a
/// byte-identical error string on every push; the outbox same-error escalation
/// fast-forwarded each row to `maxRetries` within a few cycles; `getPending` then
/// excluded the whole outbox; and the retention GC deleted the rows after the
/// window — so edits made during the outage never reached peers (silent permanent
/// divergence).
struct CloudSyncTransientRetryBudgetTests {

  @Test
  func quotaExceededAndServerResponseLostClassifyTransient() {
    #expect(CloudSyncTransientClassifier.isTransient(CKError(.quotaExceeded)))
    #expect(CloudSyncTransientClassifier.isTransient(CKError(.serverResponseLost)))
    // `zoneNotFound` is deliberately NOT transient: it has a dedicated recovery
    // path (invalidate the zone cache, recreate the zone, re-pull from nil, then
    // re-enqueue every live entity), not a plain retry-in-place, so classifying it
    // transient would let the outbox keep re-pushing into a gone zone instead of
    // triggering recovery.
    #expect(!CloudSyncTransientClassifier.isTransient(CKError(.zoneNotFound)))
  }

  /// Auth-flavored codes CloudKit can throw WHOLESALE during an iCloud
  /// token-refresh hiccup — after the cycle's account gate already passed — must
  /// classify transient. Before the classifier covered them, three such cycles
  /// stamped a byte-identical error on every pending row and the same-error
  /// escalation paused the whole outbox.
  @Test
  func authFlavoredWholesaleCodesClassifyTransient() {
    #expect(CloudSyncTransientClassifier.isTransient(CKError(.notAuthenticated)))
    #expect(CloudSyncTransientClassifier.isTransient(CKError(.accountTemporarilyUnavailable)))
    // Apple documents internalError as nonrecoverable; it must enter the
    // persistent diagnostic/recovery path rather than retry forever.
    #expect(!CloudSyncTransientClassifier.isTransient(CKError(.internalError)))
    // `permissionFailure` stays persistent: it means access was genuinely
    // revoked (a per-record rejection), not a momentary token hiccup.
    #expect(!CloudSyncTransientClassifier.isTransient(CKError(.permissionFailure)))
  }

  @Test
  func repeatedQuotaExceededPushesDoNotAdvanceTheOutboxRetryBudget() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-sy2-quota-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let service = SwiftLorvexCoreService(
      databasePath: dir.appendingPathComponent("db.sqlite").path)

    let task = try await service.createTask(title: "Edited during outage", notes: "")
    let outboxId = try #require(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)

    // Every push during a storage-full outage fails with a byte-identical
    // quotaExceeded error. Classify it exactly as the outbound coordinator does
    // and record the failure that many times — more than the same-error
    // escalation threshold — through the real outbox.
    let ckError = CKError(.quotaExceeded)
    let transient = CloudSyncTransientClassifier.isTransient(ckError)
    let message = "push chunk failed: \(ckError.localizedDescription)"
    for _ in 0..<(Int(Outbox.sameErrorEscalationThreshold) + 3) {
      try service.recordOutboundFailure(
        outboxId: outboxId, error: message, kind: transient ? .transient : .wholesale)
    }

    // The row stays pending and its retry budget
    // was never burned toward the cap.
    #expect(try service.pendingOutbound().contains { $0.outboxId == outboxId })
    let retryCount = try service.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?", arguments: [outboxId])
    }
    #expect(retryCount == 0)
  }

  /// A CloudKit token-refresh hiccup fails whole push chunks with
  /// `.notAuthenticated` after the account gate already passed, stamping the
  /// same error on every pending row each cycle. Classified transient, the rows
  /// must survive arbitrarily many such cycles with their retry budget intact.
  @Test
  func repeatedNotAuthenticatedPushesDoNotAdvanceTheOutboxRetryBudget() async throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-auth-hiccup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let service = SwiftLorvexCoreService(
      databasePath: dir.appendingPathComponent("db.sqlite").path)

    let task = try await service.createTask(title: "Edited during token refresh", notes: "")
    let outboxId = try #require(
      try service.pendingOutbound().first { $0.envelope.entityId == task.id }?.outboxId)

    let ckError = CKError(.notAuthenticated)
    let transient = CloudSyncTransientClassifier.isTransient(ckError)
    let message = "push chunk failed: \(ckError.localizedDescription)"
    for _ in 0..<(Int(Outbox.sameErrorEscalationThreshold) + 3) {
      try service.recordOutboundFailure(
        outboxId: outboxId, error: message, kind: transient ? .transient : .wholesale)
    }

    #expect(try service.pendingOutbound().contains { $0.outboxId == outboxId })
    let retryCount = try service.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT retry_count FROM sync_outbox WHERE id = ?", arguments: [outboxId])
    }
    #expect(retryCount == 0)
  }
}
