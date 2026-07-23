import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// W-1 sync-wedge regression: two devices that create the SAME habit offline each
/// mint a distinct random id but the domain normalizer derives one `lookup_key` for
/// both. On inbound sync the second habit trips the partial
/// `UNIQUE(lookup_key) WHERE archived = 0`, which historically escaped
/// ``ApplyHabit`` as ``ApplyError/db`` — a batch-fatal error that aborts the whole
/// inbound page and wedges sync forever.
///
/// The fix mirrors ``ApplyTagMerge``: the collision
/// CONVERGES instead of wedging. `min(id)` wins, the loser's synced children
/// (`habit_completions`, `habit_reminder_policies`) re-point to the winner, the loser
/// is tombstoned with a redirect, and the constraint never surfaces as
/// ``ApplyError/db``.
final class ApplyHabitMergeTests: XCTestCase {

  // `smallerId` sorts before `largerId`, so `min(id)` selects `smallerId`
  // regardless of arrival order.
  private let smallerId = "00000000-0000-7000-8000-000000000001"
  private let largerId = "ffffffff-ffff-7fff-8fff-ffffffffffff"
  private let vEarlier = "1711234567000_0000_dec0000100000001"
  private let vLater = "1711234568000_0000_dec0000200000002"
  private let ts = "2026-04-01T00:00:00.000Z"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func habitPayload(name: String, weekdays: [Int64]? = nil) throws -> String {
    var object: [String: JSONValue] = [
      "name": .string(name),
      "target_count": .int(1),
      "created_at": .string(ts),
      "updated_at": .string(ts),
    ]
    if let weekdays {
      object["frequency_type"] = .string("weekly")
      object["weekdays"] = .array(weekdays.map { .int($0) })
    } else {
      object["frequency_type"] = .string("daily")
    }
    return try SyncCanonicalize.canonicalizeJSON(.object(object))
  }

  /// Apply a habit through the applier (the path an inbound envelope drives).
  /// A non-nil `weekdays` makes it a weekly habit with that (Monday-first) set.
  private func applyHabit(
    _ db: Database, id: String, version: String, name: String = "Read", weekdays: [Int64]? = nil
  ) throws {
    try ApplyHabit.applyHabitUpsert(
      db, entityId: id, payload: try habitPayload(name: name, weekdays: weekdays), version: version,
      tieBreak: .rejectEqual, applyTs: ts)
  }

  private func aliveHabitIds(_ db: Database) throws -> [String] {
    try String.fetchAll(
      db, sql: "SELECT id FROM habits WHERE lookup_key = 'read' AND archived = 0 ORDER BY id")
  }

  private func tombstone(_ db: Database, _ id: String) throws -> Tombstone.Record? {
    try Tombstone.getTombstone(db, entityType: EntityName.habit, entityId: id)
  }

  private func redirect(_ db: Database, _ id: String) throws -> EntityRedirect.Record? {
    try EntityRedirect.get(db, sourceType: EntityName.habit, sourceId: id)
  }

  /// The incoming habit owns the SMALLER id, so it wins over the existing habit.
  func testIncomingSmallerIdWinsAndExistingIsTombstonedWithRedirect() throws {
    try withDB { db in
      try self.applyHabit(db, id: self.largerId, version: self.vEarlier)
      // Pre-fix this throws ApplyError.db (batch-fatal wedge).
      do {
        try self.applyHabit(db, id: self.smallerId, version: self.vLater)
      } catch {
        return XCTFail(
          "colliding habit must converge, not throw (got \(error)); the pre-fix bug surfaced "
            + "ApplyError.db and wedged the inbound batch")
      }

      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId])
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [self.largerId]),
        0, "the larger-id habit must be merged away")

      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
      XCTAssertNil(try self.redirect(db, self.smallerId))
    }
  }

  /// The incoming habit owns the LARGER id, so the existing smaller-id habit wins.
  func testIncomingLargerIdLosesToExistingAndIsTombstonedWithRedirect() throws {
    try withDB { db in
      try self.applyHabit(db, id: self.smallerId, version: self.vEarlier)
      do {
        try self.applyHabit(db, id: self.largerId, version: self.vLater)
      } catch {
        return XCTFail("colliding habit must converge, not throw (got \(error))")
      }

      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId])
      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
    }
  }

  /// Both convergence orders settle on the identical surviving habit id.
  func testBothArrivalOrdersConvergeToSameWinner() throws {
    var survivorA: [String] = []
    var survivorB: [String] = []
    try withDB { db in
      try self.applyHabit(db, id: self.largerId, version: self.vEarlier)
      try self.applyHabit(db, id: self.smallerId, version: self.vLater)
      survivorA = try self.aliveHabitIds(db)
    }
    try withDB { db in
      try self.applyHabit(db, id: self.smallerId, version: self.vEarlier)
      try self.applyHabit(db, id: self.largerId, version: self.vLater)
      survivorB = try self.aliveHabitIds(db)
    }
    XCTAssertEqual(survivorA, [self.smallerId])
    XCTAssertEqual(survivorA, survivorB)
  }

  /// The merged-away habit's synced children (`habit_completions`,
  /// `habit_reminder_policies`) re-point to the winner.
  func testMergeRepointsCompletionsAndPoliciesToWinner() throws {
    try withDB { db in
      // Existing (larger id) lands first and accrues a completion + a reminder policy.
      try self.applyHabit(db, id: self.largerId, version: self.vEarlier)
      try db.execute(
        sql: """
          INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, '2026-04-01', 1, ?, ?, ?)
          """,
        arguments: [self.largerId, self.vEarlier, self.ts, self.ts])
      let policyId = "00000000-0000-7000-8000-0000000000aa"
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
          VALUES (?, ?, '09:00', 1, ?, ?, ?)
          """,
        arguments: [policyId, self.largerId, self.vEarlier, self.ts, self.ts])

      // Incoming smaller id wins; the loser's children must follow it.
      try self.applyHabit(db, id: self.smallerId, version: self.vLater)

      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId])
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT habit_id FROM habit_completions WHERE completed_date = '2026-04-01'"),
        self.smallerId, "completion must re-point to the winner")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT habit_id FROM habit_reminder_policies WHERE id = ?",
          arguments: [policyId]),
        self.smallerId, "reminder policy must re-point to the winner")

      // A tag_merge conflict-log row records the dropped loser.
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
            """,
          arguments: [EntityName.habit, self.smallerId, ResolutionName.tagMerge]),
        1)
    }
  }

  /// When the winner ALSO owns a reminder policy at the loser's time, the loser's
  /// policy is a duplicate — tombstoned with a redirect to the winner's policy.
  ///
  /// Two active habits cannot share a `lookup_key` at rest (the partial UNIQUE index
  /// forbids it), so the inner merge is driven directly over two rows with distinct
  /// keys — exactly the collision the insert path stages into.
  func testMergeRedirectsDuplicateReminderPolicyToWinnerPolicy() throws {
    let winnerPolicyId = "00000000-0000-7000-8000-0000000000a1"
    let loserPolicyId = "00000000-0000-7000-8000-0000000000b1"
    try withDB { db in
      for (id, key) in [(self.smallerId, "reada"), (self.largerId, "readb")] {
        try db.execute(
          sql: """
            INSERT INTO habits (id, name, frequency_type, target_count, archived,
                                lookup_key, version, created_at, updated_at)
            VALUES (?, 'Read', 'daily', 1, 0, ?, ?, ?, ?)
            """,
          arguments: [id, key, self.vEarlier, self.ts, self.ts])
      }
      // Each habit owns a 09:00 policy — duplicates once the habits merge.
      for (pid, hid) in [(winnerPolicyId, self.smallerId), (loserPolicyId, self.largerId)] {
        try db.execute(
          sql: """
            INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
            VALUES (?, ?, '09:00', 1, ?, ?, ?)
            """,
          arguments: [pid, hid, self.vEarlier, self.ts, self.ts])
      }

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [self.largerId]),
        0, "loser habit merged away")
      // Winner keeps exactly one 09:00 policy (its own).
      XCTAssertEqual(
        try String.fetchAll(
          db, sql: "SELECT id FROM habit_reminder_policies WHERE habit_id = ?",
          arguments: [self.smallerId]),
        [winnerPolicyId])
      // The loser's duplicate policy is tombstoned with a redirect to the winner's.
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.habitReminderPolicy, entityId: loserPolicyId))
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.habitReminderPolicy, sourceId: loserPolicyId)?.targetId,
        winnerPolicyId)
    }
  }

  // MARK: - Bug 1: habit_completions content collision must be HLC-gated

  private func insertCompletion(
    _ db: Database, habitId: String, date: String, value: Int64, note: String? = nil,
    version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habit_completions (habit_id, completed_date, value, note, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [habitId, date, value, note, version, self.ts, self.ts])
  }

  private func completionValue(_ db: Database, habitId: String, date: String) throws -> Int64? {
    try Int64.fetchOne(
      db, sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
      arguments: [habitId, date])
  }

  private func insertActiveHabitPair(_ db: Database) throws {
    for (id, key) in [(self.smallerId, "reada"), (self.largerId, "readb")] {
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, frequency_type, target_count, archived,
                              lookup_key, version, created_at, updated_at)
          VALUES (?, 'Read', 'daily', 1, 0, ?, ?, ?, ?)
          """,
        arguments: [id, key, self.vEarlier, self.ts, self.ts])
    }
  }

  /// The min-id winner already occupies `(winnerId, date)` with a STALE completion;
  /// the loser being merged in carries a LATER-HLC completion at the same date.
  /// Pre-fix, `ON CONFLICT DO UPDATE` never touches `value`/`note` — the winner's
  /// stale slot survives unconditionally and the loser's later edit is silently
  /// discarded. Post-fix the later-HLC content must survive.
  func testCompletionCollisionLaterHlcLoserContentSurvivesMerge() throws {
    try withDB { db in
      try self.insertActiveHabitPair(db)
      try self.insertCompletion(
        db, habitId: self.smallerId, date: "2026-04-01", value: 1, version: self.vEarlier)
      try self.insertCompletion(
        db, habitId: self.largerId, date: "2026-04-01", value: 5, version: self.vLater)

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      XCTAssertEqual(
        try self.completionValue(db, habitId: self.smallerId, date: "2026-04-01"), 5,
        "the later-HLC completion (the loser's) must survive the merge, not whichever row "
          + "already occupied the slot")
    }
  }

  /// Both possible slot-occupancy orderings converge on the SAME (later-HLC)
  /// content: whichever side's completion carries the dominating HLC wins,
  /// regardless of which row happened to already occupy `(winnerId, date)` before
  /// the merge ran.
  func testCompletionCollisionConvergesOnLaterHlcRegardlessOfSlotOccupant() throws {
    var resultLoserDominates: Int64?
    try withDB { db in
      try self.insertActiveHabitPair(db)
      // Winner's PRE-EXISTING slot holds the OLDER completion; the loser carries
      // the later one, so its content must migrate in.
      try self.insertCompletion(
        db, habitId: self.smallerId, date: "2026-04-01", value: 1, version: self.vEarlier)
      try self.insertCompletion(
        db, habitId: self.largerId, date: "2026-04-01", value: 5, version: self.vLater)
      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)
      resultLoserDominates = try self.completionValue(
        db, habitId: self.smallerId, date: "2026-04-01")
    }

    var resultWinnerDominates: Int64?
    try withDB { db in
      try self.insertActiveHabitPair(db)
      // Winner's PRE-EXISTING slot ALREADY holds the later completion; the loser's
      // stale one must be discarded, leaving the winner's content untouched.
      try self.insertCompletion(
        db, habitId: self.smallerId, date: "2026-04-01", value: 5, version: self.vLater)
      try self.insertCompletion(
        db, habitId: self.largerId, date: "2026-04-01", value: 1, version: self.vEarlier)
      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)
      resultWinnerDominates = try self.completionValue(
        db, habitId: self.smallerId, date: "2026-04-01")
    }

    XCTAssertEqual(resultLoserDominates, 5)
    XCTAssertEqual(resultWinnerDominates, 5)
    XCTAssertEqual(
      resultLoserDominates, resultWinnerDominates,
      "the later-HLC value must survive regardless of which side already occupied the slot")
  }

  /// The discarded completion's content is not silently lost: it lands in
  /// `sync_conflict_log` as an `lww` conflict keyed on the composite
  /// `habit_completion` edge id, with the discarded `value`/`note` in the payload.
  func testCompletionCollisionLogsDiscardedContentAsLwwConflict() throws {
    try withDB { db in
      try self.insertActiveHabitPair(db)
      try self.insertCompletion(
        db, habitId: self.smallerId, date: "2026-04-01", value: 1, note: "old note",
        version: self.vEarlier)
      try self.insertCompletion(
        db, habitId: self.largerId, date: "2026-04-01", value: 5, note: "new note",
        version: self.vLater)

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT loser_version, loser_payload, resolution_type FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EdgeName.habitCompletion, "\(self.smallerId):2026-04-01"]))

      XCTAssertEqual(row["resolution_type"] as String?, ResolutionName.lww)
      XCTAssertEqual(
        row["loser_version"] as String?, self.vEarlier,
        "the discarded content's OWN original version (the winner's stale slot), not the merge version"
      )

      let payload = try XCTUnwrap(row["loser_payload"] as String?)
      let parsed = try XCTUnwrap(JSONValue.parse(payload).flatMap(ApplyJSON.object))
      XCTAssertEqual(parsed["value"], .int(1))
      XCTAssertEqual(parsed["note"], .string("old note"))
    }
  }

  /// No content, no loss, no log: when the two sides' completions carry the
  /// identical value/note, only the HLC differs, so nothing is discarded and no
  /// conflict-log row is written for the completion.
  func testCompletionCollisionWithIdenticalContentLogsNothing() throws {
    try withDB { db in
      try self.insertActiveHabitPair(db)
      try self.insertCompletion(
        db, habitId: self.smallerId, date: "2026-04-01", value: 1, version: self.vEarlier)
      try self.insertCompletion(
        db, habitId: self.largerId, date: "2026-04-01", value: 1, version: self.vLater)

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE entity_type = ?",
          arguments: [EdgeName.habitCompletion]),
        0)
    }
  }

  // MARK: - Bug 2: habit-field divergence must be captured in the conflict payload

  /// When the loser habit's own fields (icon/color/cue/frequency/target_count)
  /// diverge from the winner's, the dropped content is captured as the
  /// conflict-log `loser_payload` rather than silently discarded.
  func testMergeLogsDivergentHabitFieldsAsLoserPayload() throws {
    try withDB { db in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
                              day_of_month, target_count, archived, lookup_key, version,
                              created_at, updated_at)
          VALUES (?, 'Read', 'book', '#0000ff', 'after breakfast', 'daily', 1, NULL, 1, 0,
                  'reada', ?, ?, ?)
          """,
        arguments: [self.smallerId, self.vEarlier, self.ts, self.ts])
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
                              day_of_month, target_count, archived, lookup_key, version,
                              created_at, updated_at)
          VALUES (?, 'Read', 'moon', '#ff0000', 'before bed', 'weekly', 1, NULL, 3, 0,
                  'readb', ?, ?, ?)
          """,
        arguments: [self.largerId, self.vEarlier, self.ts, self.ts])
      // Loser's weekday set (Monday) lives in the child; the winner has none.
      try db.execute(
        sql: "INSERT INTO habit_weekdays (habit_id, weekday) VALUES (?, 0)",
        arguments: [self.largerId])

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vEarlier)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      let payload = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT loser_payload FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
            """,
          arguments: [EntityName.habit, self.smallerId, ResolutionName.tagMerge]))
      let parsed = try XCTUnwrap(JSONValue.parse(payload).flatMap(ApplyJSON.object))
      XCTAssertEqual(parsed["icon"], .string("moon"))
      XCTAssertEqual(parsed["color"], .string("#ff0000"))
      XCTAssertEqual(parsed["cue"], .string("before bed"))
      XCTAssertEqual(parsed["frequency_type"], .string("weekly"))
      XCTAssertEqual(parsed["target_count"], .int(3))
      // `weekdays` is deliberately EXCLUDED from the audit snapshot even though the
      // loser's set (Monday = 0) diverges: `habit_weekdays` is rebuilt at points
      // that differ across the two merge entry points, so comparing it here would
      // read stale/empty state rather than the final carried set.
      XCTAssertNil(parsed["weekdays"], "the weekday set must not appear in the loser payload")
    }
  }

  /// Two devices each created "Read" as a weekly habit offline with DIFFERENT
  /// weekday sets. On inbound sync they collide on `lookup_key`; the merge keeps
  /// the min id (identity) but carries the max-HLC participant's `habit_weekdays`
  /// as content, leaving no orphaned rows pointing at the merged-away loser.
  func testWeeklyWeekdaySetsCarryMaxHlcSetWithNoOrphanWeekdays() throws {
    try withDB { db in
      // Device A: the eventual identity winner (smaller id), Mon+Wed, earlier HLC.
      try self.applyHabit(
        db, id: self.smallerId, version: self.vEarlier,
        weekdays: [0, 2])
      // Device B: the eventual identity loser (larger id), Tue+Thu, LATER HLC —
      // trips the collision and its weekday set wins as content.
      do {
        try self.applyHabit(db, id: self.largerId, version: self.vLater, weekdays: [1, 3])
      } catch {
        return XCTFail("weekday-diverging habits must converge, not throw (got \(error))")
      }

      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId], "min id wins identity")
      // The winner carries the max-HLC participant's weekday set (Tue+Thu), NOT its
      // own original Mon+Wed.
      XCTAssertEqual(
        try Int64.fetchAll(
          db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday",
          arguments: [self.smallerId]),
        [1, 3])
      // No orphaned rows point at the merged-away loser.
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habit_weekdays WHERE habit_id = ?",
          arguments: [self.largerId]),
        0, "loser's habit_weekdays must cascade away, leaving no orphans")
      // And no dangling rows at all beyond the winner's two.
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM habit_weekdays"), 2)
    }
  }

  /// Equal HLCs keep the min-id habit's OWN weekday set (the tiebreak keeps the
  /// lower id as the content source, so nothing is carried).
  func testEqualHlcTiebreakKeepsMinIdWeekdays() throws {
    try withDB { db in
      try self.applyHabit(db, id: self.smallerId, version: self.vEarlier, weekdays: [0, 2])
      // Larger id, SAME HLC — collides but does not win content.
      do {
        try self.applyHabit(db, id: self.largerId, version: self.vEarlier, weekdays: [1, 3])
      } catch {
        return XCTFail("weekday-diverging habits must converge, not throw (got \(error))")
      }
      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId], "min id wins")
      XCTAssertEqual(
        try Int64.fetchAll(
          db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday",
          arguments: [self.smallerId]),
        [0, 2], "on an equal-HLC tie the min-id weekday set survives")
      XCTAssertEqual(try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM habit_weekdays"), 2)
    }
  }

  /// The max-HLC participant's scalar fields are carried onto the min-id winner,
  /// and the surviving min-id row is logged as the content-loser at its own version.
  func testMergeCarriesMaxHlcScalarContentOntoWinner() throws {
    try withDB { db in
      // smaller (min id), earlier HLC.
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
                              day_of_month, target_count, archived, lookup_key, version,
                              created_at, updated_at)
          VALUES (?, 'Read', 'book', '#0000ff', 'after breakfast', 'daily', 1, NULL, 1, 0,
                  'reada', ?, ?, ?)
          """,
        arguments: [self.smallerId, self.vEarlier, self.ts, self.ts])
      // larger (loser id) LATER HLC — its scalar content wins.
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
                              day_of_month, target_count, archived, lookup_key, version,
                              created_at, updated_at)
          VALUES (?, 'Read', 'moon', '#ff0000', 'before bed', 'daily', 1, NULL, 5, 0,
                  'readb', ?, ?, ?)
          """,
        arguments: [self.largerId, self.vLater, self.ts, self.ts])

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [(self.smallerId, self.vEarlier), (self.largerId, self.vLater)],
        triggeringVersion: self.vLater, applyTs: self.ts)

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [self.smallerId]),
        1, "min id wins identity")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [self.largerId]),
        0, "loser merged away")

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT icon, color, cue, target_count FROM habits WHERE id = ?",
          arguments: [self.smallerId]))
      XCTAssertEqual(row["icon"] as String?, "moon")
      XCTAssertEqual(row["color"] as String?, "#ff0000")
      XCTAssertEqual(row["cue"] as String?, "before bed")
      XCTAssertEqual(row["target_count"] as Int64, 5)

      // The min-id row is the content-loser: logged at its OWN version with its
      // own discarded fields.
      let clog = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT loser_version, loser_payload FROM sync_conflict_log
             WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.habit, self.smallerId]))
      XCTAssertEqual(clog["loser_version"] as String?, self.vEarlier)
      let parsed = try XCTUnwrap(
        JSONValue.parse(try XCTUnwrap(clog["loser_payload"] as String?)).flatMap(ApplyJSON.object))
      XCTAssertEqual(parsed["icon"], .string("book"))
      XCTAssertEqual(parsed["target_count"], .int(1))
    }
  }

  /// The carried weekday set converges regardless of which peer's habit arrives
  /// first (both apply orders land on the max-HLC set).
  func testWeekdayCarryConvergesBothApplyOrders() throws {
    func run(_ apply: (Database) throws -> Void) throws -> [Int64] {
      var result: [Int64] = []
      try withDB { db in
        try apply(db)
        result = try Int64.fetchAll(
          db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday",
          arguments: [self.smallerId])
      }
      return result
    }
    let orderA = try run { db in
      try self.applyHabit(db, id: self.smallerId, version: self.vEarlier, weekdays: [0, 2])
      try self.applyHabit(db, id: self.largerId, version: self.vLater, weekdays: [1, 3])
    }
    let orderB = try run { db in
      try self.applyHabit(db, id: self.largerId, version: self.vLater, weekdays: [1, 3])
      try self.applyHabit(db, id: self.smallerId, version: self.vEarlier, weekdays: [0, 2])
    }
    XCTAssertEqual(orderA, [1, 3], "max-HLC weekday set survives")
    XCTAssertEqual(orderA, orderB, "weekday content converges regardless of apply order")
  }

  // MARK: - Full inbound batch (no wedge)

  private func habitEnvelope(id: String, version: String, name: String = "Read") throws
    -> SyncEnvelope
  {
    try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try self.habitPayload(name: name), deviceId: "device-remote")
  }

  /// A full inbound page carrying the colliding habit alongside an unrelated valid
  /// habit must NOT abort: the engine never produces the batch-fatal
  /// ``ApplyError/db``, so the unrelated habit still applies.
  func testCollidingHabitDoesNotWedgeInboundBatch() throws {
    let unrelatedId = "dddddddd-dddd-7ddd-8ddd-dddddddddddd"
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    try withDB { db in
      let r1 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.habitEnvelope(id: self.smallerId, version: self.vEarlier))
      XCTAssertEqual(r1, .applied)

      do {
        _ = try Apply.applyEnvelope(
          db, registry: registry,
          envelope: try self.habitEnvelope(id: self.largerId, version: self.vLater))
      } catch let error as ApplyError {
        if case .db = error {
          return XCTFail("collision still surfaced batch-fatal ApplyError.db — sync would wedge")
        }
        return XCTFail("collision threw an unexpected ApplyError: \(error)")
      }

      // The unrelated habit (different name → different lookup_key) still applies.
      let r3 = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.habitEnvelope(id: unrelatedId, version: self.vLater, name: "Meditate"))
      XCTAssertEqual(r3, .applied)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [unrelatedId]), 1)

      XCTAssertEqual(try self.aliveHabitIds(db), [self.smallerId])
      XCTAssertNotNil(try self.tombstone(db, self.largerId))
      XCTAssertEqual(try self.redirect(db, self.largerId)?.targetId, self.smallerId)
    }
  }

  // MARK: - SYNC-MED-2: archive-interleaving non-confluence + winner re-emit

  private func habitUpsertEnvelope(
    id: String, version: String, archived: Bool, name: String = "Read"
  ) throws -> SyncEnvelope {
    let object: [String: JSONValue] = [
      "name": .string(name),
      "frequency_type": .string("daily"),
      "target_count": .int(1),
      "archived": .bool(archived),
      "created_at": .string(self.ts),
      "updated_at": .string(self.ts),
    ]
    return try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)), deviceId: "device-remote")
  }

  /// The mechanism: on the device that pulled the loser ACTIVE (merges to the
  /// winner) then ARCHIVED, the archived record redirect-remaps onto the winner
  /// and FLIPS it to archived, returning `.remapped`. A device that pulled only
  /// the archived loser never merges and leaves the winner active — the terminal
  /// divergence the winner re-emit (driven one layer up) closes.
  func testArchivedLoserRemapFlipsWinnerAndReportsRemapped() throws {
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
    let bActive = "1711234567100_0000_dec0000200000002"
    try withDB { db in
      // a active (smaller id → the eventual winner).
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.habitUpsertEnvelope(
          id: self.smallerId, version: self.vEarlier, archived: false))
      // b active (larger id) → collides on lookup_key, merges b→a.
      _ = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.habitUpsertEnvelope(id: self.largerId, version: bActive, archived: false)
      )
      // b archived (later) → b now has a permanent alias → remaps onto a and
      // flips a to archived.
      let result = try Apply.applyEnvelope(
        db, registry: registry,
        envelope: try self.habitUpsertEnvelope(
          id: self.largerId, version: self.vLater, archived: true))

      XCTAssertEqual(
        result, .remapped(fromEntityId: self.largerId, toEntityId: self.smallerId),
        "the archived loser record redirect-remaps onto the winner")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT archived FROM habits WHERE id = ?", arguments: [self.smallerId]),
        1, "the winner flipped to archived via the redirect remap")
    }
  }

  /// The re-emit target detector is scoped to habit upserts: a habit `.remapped`
  /// upsert yields the winner (`toEntityId`) as a re-emit target; a non-habit
  /// upsert and a habit delete yield nil (only habits carry the mutable
  /// `WHERE archived = 0` eligibility predicate that makes the merge non-confluent).
  func testRemappedMergeWinnerReemitTargetScopedToHabitUpserts() throws {
    try withDB { db in
      let habitUpsert = try self.habitUpsertEnvelope(
        id: self.largerId, version: self.vLater, archived: true)
      let target = try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
        db, envelope: habitUpsert, toEntityId: self.smallerId)
      XCTAssertEqual(target?.entityType, EntityName.habit)
      XCTAssertEqual(target?.entityId, self.smallerId)
      XCTAssertNil(
        target?.listFallbackPayloadListId, "a winner re-emit carries no list-fallback ledger")

      let habitDelete = SyncEnvelope(
        entityType: .habit, entityId: self.largerId, operation: .delete,
        version: try Hlc.parse(self.vLater),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "device-remote")
      XCTAssertNil(
        try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
          db, envelope: habitDelete, toEntityId: self.smallerId))

      let tagUpsert = SyncEnvelope(
        entityType: .tag, entityId: self.largerId, operation: .upsert,
        version: try Hlc.parse(self.vLater),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "device-remote")
      XCTAssertNil(
        try AbsencePreserveReemit.remappedMergeWinnerReemitTarget(
          db, envelope: tagUpsert, toEntityId: self.smallerId))
    }
  }

  // MARK: - Bug 2: deterministic merge-stamp suffix (cross-peer version convergence)

  /// A 3-participant slot collision (`V_a=(t,0,sa)`, `V_b=(t,0,sb)` with `sb>sa`,
  /// `V_c=(t,1,sc)` dominating) mints a winner version `(t, 2, sc)` whose suffix is
  /// the dominating participant's own suffix, not the local device's, so two peers
  /// with DIFFERENT device ids converge on a byte-identical winner version and
  /// scalar content regardless of fold order. Distinct `lookup_key`s let the three
  /// habits coexist at rest (active habits cannot share a key), exactly the state
  /// the insert-collision path stages into.
  func testThreeWaySlotCollisionConvergesWinnerVersionAcrossPeers() throws {
    let idA = "00000000-0000-7000-8000-00000000000a"
    let idB = "00000000-0000-7000-8000-00000000000b"
    let idC = "00000000-0000-7000-8000-00000000000c"
    let vA = "1711234567000_0000_aaaa000000000001"
    let vB = "1711234567000_0000_bbbb000000000002"
    let vC = "1711234567000_0001_cccc000000000003"
    let expectedVersion = "1711234567000_0002_cccc000000000003"

    func run(deviceId: String, rowOrder: [(String, String)]) throws -> (String?, Int64?, String?) {
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDeviceId, value: deviceId)
        for (id, icon, target, key, ver) in [
          (idA, "book", Int64(1), "reada", vA),
          (idB, "star", Int64(3), "readb", vB),
          (idC, "moon", Int64(5), "readc", vC),
        ] {
          try db.execute(
            sql: """
              INSERT INTO habits (id, name, icon, frequency_type, target_count, archived,
                                  lookup_key, version, created_at, updated_at)
               VALUES (?, 'Read', ?, 'daily', ?, 0, ?, ?, ?, ?)
              """,
            arguments: [id, icon, target, key, ver, self.ts, self.ts])
        }
        _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
          db, rows: rowOrder, triggeringVersion: vC, applyTs: self.ts)
        let row = try Row.fetchOne(
          db, sql: "SELECT icon, target_count, version FROM habits WHERE id = ?", arguments: [idA])
        return (row?["icon"] as String?, row?["target_count"] as Int64?, row?["version"] as String?)
      }
    }

    let peerOne = try run(deviceId: "device-one-1111", rowOrder: [(idA, vA), (idB, vB), (idC, vC)])
    let peerTwo = try run(deviceId: "device-two-2222", rowOrder: [(idC, vC), (idB, vB), (idA, vA)])

    XCTAssertEqual(
      peerOne.0, "moon", "content = the dominating participant (V_c), carried onto min id")
    XCTAssertEqual(peerOne.1, 5)
    XCTAssertEqual(
      peerOne.2, expectedVersion, "winner version = (maxHlc.phys, counter+1, maxHlc.suffix)")
    XCTAssertEqual(
      peerOne.0, peerTwo.0, "content byte-identical across peers with different device ids")
    XCTAssertEqual(peerOne.1, peerTwo.1)
    XCTAssertEqual(
      peerOne.2, peerTwo.2, "winner version byte-identical across peers (deterministic suffix)")
  }
}
