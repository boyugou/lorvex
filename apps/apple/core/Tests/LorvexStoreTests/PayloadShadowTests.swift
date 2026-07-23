import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports the Rust `lorvex-sync-payload::payload_shadow::tests` suite
/// (merge / shadow_strip / redirect_merge / shadow_index / size_caps /
/// corruption / schema_parity). Assertions are kept identical; seeding is via
/// the ported Swift CRUD helpers and raw SQL.
final class PayloadShadowTests: XCTestCase {
  private let entityTask = EntityKind.task.asString
  private let entityHabit = EntityKind.habit.asString
  private let entityList = EntityKind.list.asString

  private func freshDB() throws -> LorvexStore {
    try TestSupport.freshStore()
  }

  private func seedIgnoringCheckConstraints<T>(
    _ db: Database, _ body: () throws -> T
  ) throws -> T {
    try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
    do {
      let result = try body()
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      return result
    } catch {
      try? db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      throw error
    }
  }

  // MARK: - shadow_strip

  func testUpsertShadowStripsKnownKeysBeforePersisting() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-strip",
        baseVersion: "1711234567000_0000_a1b2c3d4a1b2c3d4", payloadSchemaVersion: 2,
        rawPayloadJSON:
          #"{"id":"task-strip","title":"Original","status":"open","priority":1,"version":"1711234567000_0000_a1b2c3d4a1b2c3d4","unknown_field":"keep me"}"#,
        sourceDeviceID: "device-test")

      let stored = try PayloadShadow.getShadow(
        db, entityType: self.entityTask, entityID: "task-strip")!
      let parsed = JSONValue.parse(stored.rawPayloadJSON)!
      XCTAssertEqual(parsed["unknown_field"].asString, "keep me")
      for ownedKey in PayloadShadow.ownedKeysForEntity(self.entityTask) {
        XCTAssertTrue(parsed.hasNoKey(ownedKey), "owned key \(ownedKey) should have been stripped")
      }

      let merged = try PayloadShadow.mergePayloadWithShadow(
        db, entityType: self.entityTask, entityID: "task-strip",
        knownPayload: .object([
          "id": "task-strip", "title": "Updated", "status": "completed",
        ]))
      XCTAssertEqual(merged["title"].asString, "Updated")
      XCTAssertEqual(merged["unknown_field"].asString, "keep me")
    }
  }

  func testUpsertShadowPreservesPayloadWhenNoOwnedKeysMatch() throws {
    let store = try freshDB()
    let raw = #"{"unknown_a":1,"unknown_b":"xyz"}"#
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-only-unknown",
        baseVersion: "1711234567000_0000_a1b2c3d4a1b2c3d4", payloadSchemaVersion: 2,
        rawPayloadJSON: raw, sourceDeviceID: "device-test")
      let stored = try PayloadShadow.getShadow(
        db, entityType: self.entityTask, entityID: "task-only-unknown")!
      XCTAssertEqual(stored.rawPayloadJSON, raw, "no-op strip must persist the raw form verbatim")
    }
  }

  // MARK: - merge

  func testMergePreservesUnknownFields() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-1",
        baseVersion: "1711234567000_0000_a1b2c3d4a1b2c3d4", payloadSchemaVersion: 2,
        rawPayloadJSON:
          #"{"id":"task-1","title":"Shadow","new_field":"preserve","version":"1711234567000_0000_a1b2c3d4a1b2c3d4"}"#,
        sourceDeviceID: "device-test")

      let merged = try PayloadShadow.mergePayloadWithShadow(
        db, entityType: self.entityTask, entityID: "task-1",
        knownPayload: .object(["id": "task-1", "title": "Known", "status": "open"]))
      XCTAssertEqual(merged["title"].asString, "Known")
      XCTAssertEqual(merged["status"].asString, "open")
      XCTAssertEqual(merged["new_field"].asString, "preserve")
      XCTAssertTrue(merged.hasNoKey("version"))
    }
  }

  func testMergeRejectsMalformedShadowJSON() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-1",
        baseVersion: "1711234567000_0000_a1b2c3d4a1b2c3d4", payloadSchemaVersion: 2,
        rawPayloadJSON: #"{"id":"task-1","title":"Broken""#, sourceDeviceID: "device-test")
      XCTAssertThrowsError(
        try PayloadShadow.mergePayloadWithShadow(
          db, entityType: self.entityTask, entityID: "task-1",
          knownPayload: .object(["id": "task-1", "title": "Known", "status": "open"])))
    }
  }

  // MARK: - redirect_merge

  func testRedirectMergeEqualVersionKeepsCanonicalTargetWholeShadow() throws {
    let store = try freshDB()
    let shared = "1711234567000_0001_a1b2c3d4a1b2c3d4"
    try store.writer.write { db in
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: .task, entityID: "task-target", baseVersion: shared,
          payloadSchemaVersion: 1,
          rawPayloadJSON: #"{"id":"task-target","title":"Winner","winner_only":"keep_me"}"#,
          sourceDeviceID: "device-winner", updatedAt: "2026-01-01T00:00:00Z"))
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: .task, entityID: "task-source", baseVersion: shared,
          payloadSchemaVersion: 1,
          rawPayloadJSON: #"{"id":"task-source","title":"Loser","loser_only":"forward_compat"}"#,
          sourceDeviceID: "device-loser", updatedAt: "2026-01-01T00:00:00Z"))

      try PayloadShadow.mergeShadowIntoRedirect(
        db, fromEntityType: self.entityTask, fromEntityID: "task-source",
        toEntityType: self.entityTask, toEntityID: "task-target")

      let merged = try PayloadShadow.getShadow(
        db, entityType: self.entityTask, entityID: "task-target")!
      let json = JSONValue.parse(merged.rawPayloadJSON)!
      XCTAssertEqual(json["winner_only"].asString, "keep_me")
      XCTAssertTrue(
        json.hasNoKey("loser_only"),
        "equal-HLC redirect consolidation must not synthesize a key union")
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-source"))
    }
  }

  /// Redirect consolidation chooses one complete content shadow. It never
  /// unions independent future-field namespaces, so two individually legal
  /// shadows cannot create an over-cap hybrid payload.
  func testRedirectMergeSelectsNewerWholeShadowWithoutUnionCapOverflow() throws {
    let store = try freshDB()
    // Each blob is ~150 KiB (individually ≤ 256 KiB cap); the union of the two
    // distinct keys is ~300 KiB, over the cap.
    let halfCap = PayloadShadow.maxRawPayloadJSONBytes * 3 / 5
    let winnerBlob = String(repeating: "w", count: halfCap)
    let loserBlob = String(repeating: "l", count: halfCap)
    let older = "1711234567000_0001_a1b2c3d4a1b2c3d4"
    let newer = "1711234567001_0001_a1b2c3d4a1b2c3d4"
    try store.writer.write { db in
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: .task, entityID: "task-target", baseVersion: older,
          payloadSchemaVersion: 1,
          rawPayloadJSON: try canonicalizeJSON(.object(["winner_blob": .string(winnerBlob)])),
          sourceDeviceID: "device-winner", updatedAt: "2026-01-01T00:00:00Z"))
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: .task, entityID: "task-source", baseVersion: newer,
          payloadSchemaVersion: 1,
          rawPayloadJSON: try canonicalizeJSON(.object(["loser_blob": .string(loserBlob)])),
          sourceDeviceID: "device-loser", updatedAt: "2026-01-01T00:00:00Z"))

      XCTAssertNoThrow(
        try PayloadShadow.mergeShadowIntoRedirect(
          db, fromEntityType: self.entityTask, fromEntityID: "task-source",
          toEntityType: self.entityTask, toEntityID: "task-target"),
        "whole-row selection must not manufacture an over-cap union")

      // The newer source content moves to the canonical target identity.
      let winner = try PayloadShadow.getShadow(
        db, entityType: self.entityTask, entityID: "task-target")
      let winnerJSON = JSONValue.parse(try XCTUnwrap(winner).rawPayloadJSON)!
      XCTAssertEqual(winnerJSON["loser_blob"].asString, loserBlob)
      XCTAssertTrue(winnerJSON.hasNoKey("winner_blob"))
      XCTAssertEqual(winner?.baseVersion, newer)
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-source"))
    }
  }

  // MARK: - size_caps

  func testRestoreShadowRejectsOversizeRawPayloadJSON() throws {
    let store = try freshDB()
    let oversize = String(repeating: "x", count: PayloadShadow.maxRawPayloadJSONBytes + 1)
    try store.writer.write { db in
      let row = PayloadShadow.Row(
        entityType: .task, entityID: "task-bomb",
        baseVersion: "0001000000000_0001_de1cea1234567000", payloadSchemaVersion: 1,
        rawPayloadJSON: oversize, sourceDeviceID: "device-import",
        updatedAt: "2026-04-19T08:00:00.000Z")
      XCTAssertThrowsError(try PayloadShadow.restoreShadow(db, row: row)) { err in
        guard case PayloadError.validation(let m) = err else {
          return XCTFail("expected PayloadError.validation, got \(err)")
        }
        XCTAssertTrue(m.contains("exceeds maximum"))
      }
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-bomb"))
    }
  }

  func testUpsertShadowRejectsOversizeRawPayloadJSON() throws {
    let store = try freshDB()
    let oversize = String(repeating: "y", count: PayloadShadow.maxRawPayloadJSONBytes + 1)
    try store.writer.write { db in
      XCTAssertThrowsError(
        try PayloadShadow.upsertShadow(
          db, entityType: self.entityTask, entityID: "task-bomb-up",
          baseVersion: "0001000000000_0001_de1cea1234567000", payloadSchemaVersion: 1,
          rawPayloadJSON: oversize, sourceDeviceID: "device-local")
      ) { err in
        guard case PayloadError.validation(let m) = err else {
          return XCTFail("expected PayloadError.validation, got \(err)")
        }
        XCTAssertTrue(m.contains("exceeds maximum"))
      }
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-bomb-up"))
    }
  }

  // MARK: - reap

  func testStrictShadowReapKeepsEqualVersionAndDropsNewerVersion() throws {
    let store = try freshDB()
    let baseVersion = "1711234567000_0000_a1b2c3d4a1b2c3d4"
    let newerVersion = "1711234567001_0000_a1b2c3d4a1b2c3d4"
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-strict-reap",
        baseVersion: baseVersion, payloadSchemaVersion: 2,
        rawPayloadJSON: #"{"unknown_field":"keep until a strictly newer winner"}"#,
        sourceDeviceID: "device-test")

      try PayloadShadow.removeShadowIfStrictlySuperseded(
        db, entityType: self.entityTask, entityID: "task-strict-reap", version: baseVersion)
      XCTAssertNotNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-strict-reap"))

      try PayloadShadow.removeShadowIfStrictlySuperseded(
        db, entityType: self.entityTask, entityID: "task-strict-reap", version: newerVersion)
      XCTAssertNil(
        try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-strict-reap"))
    }
  }

  func testNonStrictShadowReapDropsEqualVersion() throws {
    let store = try freshDB()
    let baseVersion = "1711234567000_0000_a1b2c3d4a1b2c3d4"
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-nonstrict-reap",
        baseVersion: baseVersion, payloadSchemaVersion: 2,
        rawPayloadJSON: #"{"unknown_field":"finalized"}"#,
        sourceDeviceID: "device-test")

      try PayloadShadow.removeShadowIfSuperseded(
        db, entityType: self.entityTask, entityID: "task-nonstrict-reap", version: baseVersion)
      XCTAssertNil(
        try PayloadShadow.getShadow(
          db, entityType: self.entityTask, entityID: "task-nonstrict-reap"))
    }
  }

  func testKnownLegacyPreparationRejectsVersionBehindHigherSchemaShadow() throws {
    let store = try freshDB()
    let shadowVersion = "1711234567001_0000_a1b2c3d4a1b2c3d4"
    let olderIncoming = "1711234567000_0000_a1b2c3d4a1b2c3d4"
    try store.writer.write { db in
      try PayloadShadow.upsertShadow(
        db, entityType: self.entityTask, entityID: "task-legacy-invariant",
        baseVersion: shadowVersion, payloadSchemaVersion: 2,
        rawPayloadJSON: #"{"unknown_field":"retain on invariant failure"}"#,
        sourceDeviceID: "device-test")

      XCTAssertThrowsError(
        try PayloadShadow.prepareForKnownSchemaUpsert(
          db, entityType: self.entityTask, entityID: "task-legacy-invariant",
          incomingPayloadSchemaVersion: 1, incomingVersion: olderIncoming)
      ) { error in
        guard case .invariant(let message) = error as? PayloadError else {
          return XCTFail("expected payload invariant, got \(error)")
        }
        XCTAssertTrue(message.contains("precedes its higher-schema payload shadow"))
      }
      XCTAssertEqual(
        try PayloadShadow.getShadow(
          db, entityType: self.entityTask, entityID: "task-legacy-invariant")?.baseVersion,
        shadowVersion)
    }
  }

  // MARK: - corruption

  func testRemoveShadowIfSupersededDropsCorruptedShadowRowInsteadOfFailing() throws {
    let store = try freshDB()
    try store.writer.write { db in
      try self.seedIgnoringCheckConstraints(db) {
        try PayloadShadow.restoreShadow(
          db,
          row: PayloadShadow.Row(
            entityType: .task, entityID: "task-1", baseVersion: "not-a-valid-hlc",
            payloadSchemaVersion: 2, rawPayloadJSON: #"{"id":"task-1","title":"Shadow"}"#,
            sourceDeviceID: "token=secret", updatedAt: "2026-01-01T00:00:00Z"))
      }

      XCTAssertNoThrow(
        try PayloadShadow.removeShadowIfSuperseded(
          db, entityType: self.entityTask, entityID: "task-1",
          version: "1711234567000_0000_a1b2c3d4a1b2c3d4"))
      XCTAssertNil(try PayloadShadow.getShadow(db, entityType: self.entityTask, entityID: "task-1"))

      let row = try Row.fetchOne(
        db, sql: "SELECT source, level, message, details FROM error_logs")!
      XCTAssertEqual(row["source"], "store.payload_shadow.corrupted_base_version")
      XCTAssertEqual(row["level"], "warn")
      XCTAssertEqual(row["message"], "corrupted base_version on persisted payload shadow")
      XCTAssertEqual(
        row["details"],
        "entity_type=task entity_id=task-1 base_version=not-a-valid-hlc "
          + "source_device_id=[REDACTED] error=validation error: invalid HLC in payload shadow "
          + "base_version: not-a-valid-hlc")
    }
  }

  // MARK: - schema_parity

  func testPayloadShadowSchemaParity() throws {
    let entityToTable: [String: String] = [
      EntityKind.task.asString: "tasks",
      EntityKind.list.asString: "lists",
      EntityKind.habit.asString: "habits",
      EntityKind.tag.asString: "tags",
      EntityKind.calendarEvent.asString: "calendar_events",
      EntityKind.preference.asString: "preferences",
      EntityKind.memory.asString: "memories",
      EntityKind.dailyReview.asString: "daily_reviews",
      EntityKind.currentFocus.asString: "current_focus",
      EntityKind.focusSchedule.asString: "focus_schedule",
      EntityKind.taskReminder.asString: "task_reminders",
      EntityKind.taskChecklistItem.asString: "task_checklist_items",
      EntityKind.habitReminderPolicy.asString: "habit_reminder_policies",
      EntityKind.aiChangelog.asString: "ai_changelog",
      EntityKind.taskTag.asString: "task_tags",
      EntityKind.taskDependency.asString: "task_dependencies",
      EntityKind.taskCalendarEventLink.asString: "task_calendar_event_links",
      EntityKind.habitCompletion.asString: "habit_completions",
    ]

    let schemaOnlyExceptions: [String: Set<String>] = [
      EntityKind.task.asString: ["priority_effective"],
      EntityKind.calendarEvent.asString: ["recurrence_end_date"],
    ]

    let payloadOnlySynthetics: [String: Set<String>] = [
      EntityKind.calendarEvent.asString: ["recurrence_exceptions"],
      EntityKind.currentFocus.asString: ["task_ids"],
      EntityKind.focusSchedule.asString: ["blocks"],
      EntityKind.dailyReview.asString: ["linked_task_ids", "linked_list_ids"],
      EntityKind.task.asString: ["recurrence_exceptions"],
      // `entity_ids` materializes into a join table; `version` is injected by
      // the generic outbox funnel. `cloud_presence_possible` was an obsolete
      // local evidence column and remains denylisted so an untrusted peer cannot
      // preserve and relay that reserved key through a payload shadow.
      EntityKind.aiChangelog.asString: [
        "entity_ids", "version", "cloud_presence_possible",
      ],
      // `weekdays` rides in the habit payload but materializes into the
      // `habit_weekdays` child, not a `habits` column.
      EntityKind.habit.asString: ["weekdays"],
    ]

    let store = try freshDB()
    try store.writer.read { db in
      var failures: [String] = []
      for (entityType, table) in entityToTable {
        let allSchemaCols = Set(
          try String.fetchAll(
            db, sql: "SELECT name FROM pragma_table_info(?) ORDER BY cid", arguments: [table]))
        // Device-local routing need not be part of the wire projection, but may
        // still be shadow-owned so an inbound payload cannot relay it.
        let wireSchemaCols = allSchemaCols.filter {
          !StorageSchema.isDeviceLocalColumn(table: table, column: $0)
        }
        XCTAssertFalse(allSchemaCols.isEmpty, "table \(table) for \(entityType) has no columns")

        let owned = Set(PayloadShadow.ownedKeysForEntity(entityType))
        XCTAssertFalse(owned.isEmpty, "ownedKeysForEntity(\(entityType)) returned empty")

        let exceptions = schemaOnlyExceptions[entityType] ?? []
        let synthetics = payloadOnlySynthetics[entityType] ?? []

        let schemaNotOwned = wireSchemaCols.filter {
          !owned.contains($0) && !exceptions.contains($0)
        }
        if !schemaNotOwned.isEmpty {
          failures.append(
            "\(entityType) (table \(table)): schema columns missing from ownedKeys: "
              + "\(schemaNotOwned.sorted())")
        }
        let ownedNotSchema = owned.filter {
          !allSchemaCols.contains($0) && !synthetics.contains($0)
        }
        if !ownedNotSchema.isEmpty {
          failures.append(
            "\(entityType) (table \(table)): ownedKeys entries missing from schema: "
              + "\(ownedNotSchema.sorted())")
        }
      }
      XCTAssertTrue(
        failures.isEmpty,
        "owned-keys ↔ schema parity failed:\n  - \(failures.joined(separator: "\n  - "))")
    }
  }

  func testAiChangelogReservedLocalKeysAreStrippedFromPayloadShadow() throws {
    let trimmed = try XCTUnwrap(
      PayloadShadow.stripKnownKeysForShadow(
        entityType: EntityName.aiChangelog,
        rawPayloadJSON:
          #"{"cloud_presence_possible":true,"future_field":"keep","retention_account_identifier":"never-relay"}"#
      ))
    guard case .object(let object)? = JSONValue.parse(trimmed) else {
      return XCTFail("trimmed shadow must be an object")
    }
    XCTAssertEqual(object["future_field"], .string("keep"))
    XCTAssertNil(object["retention_account_identifier"])
    XCTAssertNil(object["cloud_presence_possible"])
  }
}
