import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// D3 convergence coverage for the habit-completion merge stamp.
///
/// When a duplicate habit is merged, its `habit_completions` (a content-carrying
/// composite edge: `value`/`note`) re-point to the winner. Stamping the surviving
/// completion at `mergeVersion` erases its authored HLC, so a genuinely-newer
/// completion edge that arrives AFTER the merge loses the per-edge LWW gate to the
/// merge stamp — the two devices diverge (one keeps the stale value forever), and
/// a stale pre-merge edge can regress newer content. Preserving each surviving
/// completion's ORIGINAL version keeps per-edge LWW arbitration intact.
///
/// These tests run on top of the D2 composite-edge parent-redirect remap: a
/// completion edge authored against the merged-loser habit is remapped onto the
/// winner before its LWW gate.
final class ApplyHabitCompletionMergeVersionTests: XCTestCase {

  // winnerHabit < loserHabit lexicographically → min-id merge keeps the winner.
  private let winnerHabit = "00000000-0000-7000-8000-000000000001"
  private let loserHabit = "00000000-0000-7000-8000-000000000002"
  private let date = "2026-04-01"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func habitPayload() throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "name": .string("Read"),
        "frequency_type": .string("daily"),
        "target_count": .int(1),
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
      ]))
  }

  private func habitEnvelope(_ id: String, _ version: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: try habitPayload(),
      deviceId: "device-remote")
  }

  private func completionEnvelope(
    _ habitId: String, value: Int64, version: String
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "habit_id": .string(habitId),
        "completed_date": .string(date),
        "value": .int(value),
        "note": .null,
        "created_at": .string("2026-04-01T08:00:00Z"),
        "updated_at": .string("2026-04-01T08:00:00Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habitCompletion, entityId: "\(habitId):\(date)", operation: .upsert,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "device-remote")
  }

  private func apply(_ db: Database, _ env: SyncEnvelope) throws {
    let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
    if case let .deferred(reason) = result {
      try PendingInboxDrain.enqueueDeferred(db, envelope: env, reason: reason)
    }
  }

  private func winnerCompletionValue(_ db: Database) throws -> Int64? {
    try Int64.fetchOne(
      db, sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
      arguments: [winnerHabit, date])
  }

  // MARK: - Consequence #1: 2-device completion divergence

  /// Device stream where the merge runs while ONLY the loser's completion is
  /// present (winner's not-yet-arrived); the loser completion re-points to the
  /// winner, then the winner-side (genuinely-newer) completion arrives.
  private func runMergeBeforeWinnerCompletion(
    habitVersion: String, loserValue: Int64, loserVersion: String,
    winnerValue: Int64, winnerVersion: String
  ) throws -> Int64? {
    let store = try SyncTestSupport.freshStore()
    return try store.writer.write { db in
      try self.apply(db, try self.habitEnvelope(self.loserHabit, habitVersion))
      try self.apply(
        db, try self.completionEnvelope(self.loserHabit, value: loserValue, version: loserVersion))
      // Incoming winner habit (min id) collides on lookup_key → merge; the loser's
      // completion re-points onto the winner.
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, habitVersion))
      // The winner-side completion edge arrives last.
      try self.apply(
        db, try self.completionEnvelope(self.winnerHabit, value: winnerValue, version: winnerVersion))
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      return try self.winnerCompletionValue(db)
    }
  }

  /// Device stream where the winner's completion is present at merge time (an
  /// in-merge same-date content collision), then the loser's stale completion
  /// replays (remapped onto the winner via D2).
  private func runMergeWithWinnerCompletionPresent(
    habitVersion: String, loserValue: Int64, loserVersion: String,
    winnerValue: Int64, winnerVersion: String
  ) throws -> Int64? {
    let store = try SyncTestSupport.freshStore()
    return try store.writer.write { db in
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, habitVersion))
      try self.apply(
        db, try self.completionEnvelope(self.winnerHabit, value: winnerValue, version: winnerVersion))
      try self.apply(db, try self.habitEnvelope(self.loserHabit, habitVersion))
      try self.apply(
        db, try self.completionEnvelope(self.loserHabit, value: loserValue, version: loserVersion))
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      return try self.winnerCompletionValue(db)
    }
  }

  /// The genuinely-newer completion (value=1, vNewer) must win on BOTH devices,
  /// regardless of whether the merge saw it or re-pointed the older one first.
  /// `habitVersion` is deliberately higher than the completion versions (a
  /// recently-edited habit triggering the dedup) so the buggy mergeVersion stamp
  /// would dominate `vNewer` and pin the stale value.
  func testCompletionDivergenceConvergesToNewerValue() throws {
    let habitVersion = "1711000009000_0000_1111000011110000"
    let vOlder = "1711000001000_0000_bbbb0000bbbb0000"  // loser, value=2
    let vNewer = "1711000005000_0000_aaaa0000aaaa0000"  // winner, value=1 (newer)

    let mergeBeforeWinner = try runMergeBeforeWinnerCompletion(
      habitVersion: habitVersion, loserValue: 2, loserVersion: vOlder,
      winnerValue: 1, winnerVersion: vNewer)
    let winnerPresent = try runMergeWithWinnerCompletionPresent(
      habitVersion: habitVersion, loserValue: 2, loserVersion: vOlder,
      winnerValue: 1, winnerVersion: vNewer)

    XCTAssertEqual(mergeBeforeWinner, 1, "the genuinely-newer completion must survive the merge stamp")
    XCTAssertEqual(winnerPresent, 1)
    XCTAssertEqual(
      mergeBeforeWinner, winnerPresent,
      "both device orderings must converge on the newer completion value")
  }

  // MARK: - Consequence #2: version regression

  /// A completion whose version EXCEEDS the merge version (completions written
  /// daily, habits rarely edited) is re-pointed by the merge. Stamping it DOWN to
  /// mergeVersion lets a stale pre-merge edge — version between mergeVersion and
  /// the completion's true version — later overwrite the newer content. Preserving
  /// the original version blocks the regression.
  func testStalePreMergeEdgeDoesNotRegressRepointedCompletion() throws {
    let habitVersion = "1711000001000_0000_1111000011110000"  // low → low mergeVersion
    let vHigh = "1711000009000_0000_3333000033330000"  // re-pointed completion (value=2)
    let vStale = "1711000005000_0000_4444000044440000"  // stale edge, > mergeVersion, < vHigh

    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.apply(db, try self.habitEnvelope(self.loserHabit, habitVersion))
      try self.apply(
        db, try self.completionEnvelope(self.loserHabit, value: 2, version: vHigh))
      // Merge re-points the high-version completion onto the winner.
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, habitVersion))
      // A stale edit (older than the completion's true version, but newer than the
      // low merge version) must NOT overwrite the re-pointed content.
      try self.apply(
        db, try self.completionEnvelope(self.winnerHabit, value: 99, version: vStale))
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      XCTAssertEqual(
        try self.winnerCompletionValue(db), 2,
        "a stale pre-merge edge must not overwrite a re-pointed completion whose true version "
          + "dominates it")
    }
  }
}
