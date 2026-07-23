import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Defense-in-depth classification at inner applier semantic boundaries.
///
/// Direct applier calls pin the fallback rule: a manifest-opaque semantic miss
/// on a newer schema defers intact, while the same miss on a current schema is
/// invalid. Production `Apply.applyEnvelope` first enforces the numbered
/// manifest, so drift in a frozen enum or closed nested shape rejects before
/// these inner helpers run. The end-to-end cases below pin that stricter
/// production boundary separately.
final class ApplyForwardCompatTests: XCTestCase {

  private let vMid = "1711234568000_0000_dec0000100000001"
  private let localMax = LorvexVersion.payloadSchemaVersion
  private var newer: UInt32 { LorvexVersion.payloadSchemaVersion + 1 }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func canon(_ value: JSONValue) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(value)
  }

  private func registry() -> EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func envelope(
    _ kind: EntityKind, _ id: String, _ payload: JSONValue, schema: UInt32,
    version: String? = nil
  ) throws -> SyncEnvelope {
    let wireVersion = version ?? vMid
    return SyncEnvelope(
      entityType: kind, entityId: id, operation: .upsert, version: try Hlc.parse(wireVersion),
      payloadSchemaVersion: schema, payload: try canon(payload), deviceId: "device-remote")
  }

  // MARK: - assertion helpers

  /// A newer-schema miss at a directly-invoked inner boundary surfaces the
  /// retention sentinel carrying a `schemaTooNew` reason.
  private func assertForwardCompatDefer(
    _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
      guard case ApplyError.deferForwardCompat(let reason) = error else {
        return XCTFail("expected .deferForwardCompat, got \(error)", file: file, line: line)
      }
      guard case .schemaTooNew = reason else {
        return XCTFail("expected .schemaTooNew reason, got \(reason)", file: file, line: line)
      }
    }
  }

  /// A same-version miss at an inner boundary still drops as invalid payload.
  private func assertInvalidPayloadDrop(
    _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
      guard case ApplyError.invalidPayload = error else {
        return XCTFail(
          "same-version unknown enum must DROP as .invalidPayload, got \(error)",
          file: file, line: line)
      }
    }
  }

  // MARK: - payload builders

  private func calendarPayload(
    eventType: String = "event", recurrence: String? = nil
  ) -> JSONValue {
    var obj: [String: JSONValue] = [
      "title": .string("Standup"),
      "start_date": .string("2026-04-20"),
      "start_time": .string("09:00"),
      "all_day": .bool(false),
      "event_type": .string(eventType),
      "occurrence_state": .null,
      "content_version": .string(vMid),
      "recurrence_generation": recurrence == nil ? .null : .string(vMid),
      "recurrence_instance_date": .null,
      "recurrence_topology_version": .string(vMid),
      "series_cutover_id": .null,
      "series_id": .null,
      "created_at": .string("2026-04-20T09:00:00.000Z"),
      "updated_at": .string("2026-04-20T09:00:00.000Z"),
    ]
    if let recurrence { obj["recurrence"] = .string(recurrence) }
    return .object(obj)
  }

  private func habitPayload(frequencyType: String) -> JSONValue {
    .object([
      "name": .string("Read"), "frequency_type": .string(frequencyType),
      "target_count": .int(1),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ])
  }

  private func taskPayload(status: String = "open", deferReason: String? = nil) -> JSONValue {
    var obj: [String: JSONValue] = [
      "title": .string("A task"), "status": .string(status),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    if let deferReason { obj["last_defer_reason"] = .string(deferReason) }
    return .object(obj)
  }

  private func focusSchedulePayload(
    blockType: String, date: String = "2026-04-01", version: String? = nil,
    start: Int64 = 540, end: Int64 = 570,
    blockExtras: [String: JSONValue] = [:], topLevelExtras: [String: JSONValue] = [:]
  ) -> JSONValue {
    var block: [String: JSONValue] = [
      "block_type": .string(blockType), "start_minutes": .int(start), "end_minutes": .int(end),
      "calendar_event_id": .null, "event_source": .null, "task_id": .null, "title": .null,
    ]
    block.merge(blockExtras) { _, extra in extra }
    var payload: [String: JSONValue] = [
      "date": .string(date),
      "rationale": .null,
      "timezone": .null,
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
      "version": .string(version ?? vMid),
      "blocks": .array([.object(block)]),
    ]
    payload.merge(topLevelExtras) { _, extra in extra }
    return .object(payload)
  }

  private func productionCalendarPayload(
    id: String, recurrence: String, version: String? = nil
  ) -> JSONValue {
    .object([
      "all_day": .bool(false),
      "attendees": .array([]),
      "color": .null,
      "content_version": .string(version ?? vMid),
      "created_at": .string("2026-04-01T09:00:00.000Z"),
      "description": .null,
      "end_date": .string("2026-04-01"),
      "end_time": .string("10:00"),
      "event_type": .string("event"),
      "id": .string(id),
      "location": .null,
      "occurrence_state": .null,
      "person_name": .null,
      "recurrence": .string(recurrence),
      "recurrence_generation": .string(version ?? vMid),
      "recurrence_instance_date": .null,
      "recurrence_topology_version": .string(version ?? vMid),
      "series_cutover_id": .null,
      "series_id": .null,
      "start_date": .string("2026-04-01"),
      "start_time": .string("09:00"),
      "timezone": .string("America/Los_Angeles"),
      "title": .string("Future recurrence"),
      "updated_at": .string("2026-04-01T09:00:00.000Z"),
      "url": .null,
      "version": .string(version ?? vMid),
    ])
  }

  // MARK: - Direct inner gates: newer defers, same schema drops

  func testEventTypeForwardCompat() throws {
    try withDB { db in
      self.assertForwardCompatDefer {
        try ApplyCalendarEvent.applyCalendarEventUpsert(
          db, entityId: "ce-1", payload: try self.canon(self.calendarPayload(eventType: "webinar")),
          version: self.vMid, tieBreak: .rejectEqual, applyTs: "2026-04-20T09:00:00.000Z",
          payloadSchemaVersion: self.newer)
      }
      self.assertInvalidPayloadDrop {
        try ApplyCalendarEvent.applyCalendarEventUpsert(
          db, entityId: "ce-1", payload: try self.canon(self.calendarPayload(eventType: "webinar")),
          version: self.vMid, tieBreak: .rejectEqual, applyTs: "2026-04-20T09:00:00.000Z",
          payloadSchemaVersion: self.localMax)
      }
    }
  }

  func testRecurrenceFreqForwardCompat() throws {
    try withDB { db in
      let payload = try self.canon(
        self.calendarPayload(recurrence: #"{"FREQ":"FORTNIGHTLY"}"#))
      self.assertForwardCompatDefer {
        try ApplyCalendarEvent.applyCalendarEventUpsert(
          db, entityId: "ce-2", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          applyTs: "2026-04-20T09:00:00.000Z", payloadSchemaVersion: self.newer)
      }
      self.assertInvalidPayloadDrop {
        try ApplyCalendarEvent.applyCalendarEventUpsert(
          db, entityId: "ce-2", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          applyTs: "2026-04-20T09:00:00.000Z", payloadSchemaVersion: self.localMax)
      }
    }
  }

  func testFrequencyTypeForwardCompat() throws {
    try withDB { db in
      let payload = try self.canon(self.habitPayload(frequencyType: "yearly"))
      self.assertForwardCompatDefer {
        try ApplyHabit.applyHabitUpsert(
          db, entityId: "h-1", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          applyTs: "2026-04-20T09:00:00.000Z", payloadSchemaVersion: self.newer)
      }
      self.assertInvalidPayloadDrop {
        try ApplyHabit.applyHabitUpsert(
          db, entityId: "h-1", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          applyTs: "2026-04-20T09:00:00.000Z", payloadSchemaVersion: self.localMax)
      }
    }
  }

  func testTaskStatusForwardCompat() throws {
    try withDB { db in
      let payload = try self.canon(self.taskPayload(status: "archived"))
      self.assertForwardCompatDefer {
        _ = try ApplyTask.buildTaskRow(
          db, taskId: "t-1", payload: payload, version: self.vMid, payloadSchemaVersion: self.newer)
      }
      self.assertInvalidPayloadDrop {
        _ = try ApplyTask.buildTaskRow(
          db, taskId: "t-1", payload: payload, version: self.vMid,
          payloadSchemaVersion: self.localMax)
      }
    }
  }

  func testDeferReasonForwardCompat() throws {
    try withDB { db in
      let payload = try self.canon(self.taskPayload(deferReason: "procrastination"))
      self.assertForwardCompatDefer {
        _ = try ApplyTask.buildTaskRow(
          db, taskId: "t-2", payload: payload, version: self.vMid, payloadSchemaVersion: self.newer)
      }
      self.assertInvalidPayloadDrop {
        _ = try ApplyTask.buildTaskRow(
          db, taskId: "t-2", payload: payload, version: self.vMid,
          payloadSchemaVersion: self.localMax)
      }
    }
  }

  func testBlockTypeForwardCompat() throws {
    // `block_type` parses AFTER the LWW-gated parent focus_schedule upsert, so
    // each schema is exercised in its own fresh store (a second same-version
    // upsert of the same date would be LWW-rejected and never reach block parse).
    let payload = try canon(focusSchedulePayload(blockType: "meeting"))
    try withDB { db in
      self.assertForwardCompatDefer {
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: "2026-04-01", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          payloadSchemaVersion: self.newer)
      }
    }
    try withDB { db in
      self.assertInvalidPayloadDrop {
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: "2026-04-01", payload: payload, version: self.vMid, tieBreak: .rejectEqual,
          payloadSchemaVersion: self.localMax)
      }
    }
  }

  // MARK: - end-to-end applyEnvelope: atomic defer (savepoint rollback)

  /// A known typed field cannot acquire an unrecognized value merely because
  /// the envelope declares a future schema. Production preflight rejects it
  /// before dispatch, leaving no partial aggregate state.
  func testApplyEnvelopeFutureBlockTypeRejectsAtomically() throws {
    try withDB { db in
      let env = try self.envelope(
        .focusSchedule, "2026-04-01", self.focusSchedulePayload(blockType: "meeting"),
        schema: self.newer)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: env)
      ) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected .invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("block_type"))
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: ["2026-04-01"]),
        0, "parent focus_schedule row must be rolled back on a forward-compat defer")
    }
  }

  /// Same-version unknown enum through the full pipeline still DROPS: applyEnvelope
  /// throws `.invalidPayload` (not `.deferred`), and the savepoint leaves nothing.
  func testApplyEnvelopeSameVersionUnknownBlockTypeStillThrowsInvalidPayload() throws {
    try withDB { db in
      let env = try self.envelope(
        .focusSchedule, "2026-04-01", self.focusSchedulePayload(blockType: "meeting"),
        schema: self.localMax)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: env)
      ) { error in
        guard case ApplyError.invalidPayload = error else {
          return XCTFail("same-version unknown block_type must throw .invalidPayload, got \(error)")
        }
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: ["2026-04-01"]),
        0)
    }
  }

  /// Future schemas may add unknown top-level fields only. A nested key inside a
  /// known closed object is not shadow-preservable and rejects atomically.
  func testApplyEnvelopeFutureNestedBlockKeyRejectsAtomically() throws {
    try withDB { db in
      let env = try self.envelope(
        .focusSchedule, "2026-04-01",
        self.focusSchedulePayload(
          blockType: "buffer", blockExtras: ["future_context": .string("preserve intact")]),
        schema: self.newer)

      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: env)
      ) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected .invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("future_context"))
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?",
          arguments: ["2026-04-01"]), 0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: ["2026-04-01"]), 0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.focusSchedule, "2026-04-01"]), 0)
    }
  }

  /// Without a newer schema declaration, an unknown nested key is corruption,
  /// not forward-compatible data. It must reject as invalid and leave no state.
  func testApplyEnvelopeSameVersionUnknownNestedBlockKeyRejectsAtomically() throws {
    try withDB { db in
      let env = try self.envelope(
        .focusSchedule, "2026-04-01",
        self.focusSchedulePayload(
          blockType: "buffer", blockExtras: ["future_context": .string("undeclared")]),
        schema: self.localMax)

      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: env)
      ) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected .invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("future_context"))
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?",
          arguments: ["2026-04-01"]), 0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: ["2026-04-01"]), 0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.focusSchedule, "2026-04-01"]), 0)
    }
  }

  /// Top-level additions remain the safe additive path: a next-schema key is
  /// shadowed while all locally-known aggregate and block fields still apply.
  func testApplyEnvelopeFutureTopLevelKeyAppliesAndRemainsInShadow() throws {
    try withDB { db in
      let env = try self.envelope(
        .focusSchedule, "2026-04-01",
        self.focusSchedulePayload(
          blockType: "buffer",
          topLevelExtras: ["future_context": .string("preserved through old peer")]),
        schema: self.newer)

      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: env), .applied)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?",
          arguments: ["2026-04-01"]), 1)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: ["2026-04-01"]), 1)

      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: "2026-04-01"))
      guard case .object(let shadowObject)? = JSONValue.parse(shadow.rawPayloadJSON) else {
        return XCTFail("expected object payload shadow")
      }
      XCTAssertEqual(shadowObject["future_context"], .string("preserved through old peer"))
      XCTAssertNil(shadowObject["blocks"], "known aggregate keys must not be duplicated in shadow")
    }
  }

  func testLegacyUpdateRetainsHigherSchemaShadowAndAdvancesItsBase() throws {
    try withDB { db in
      let entityID = "2026-04-03"
      let later = "1711234568001_0000_dec0000100000002"
      let future = try self.envelope(
        .focusSchedule, entityID,
        self.focusSchedulePayload(
          blockType: "buffer", date: entityID,
          topLevelExtras: ["future_context": .string("survives legacy update")]),
        schema: self.newer)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: future), .applied)

      let legacy = try self.envelope(
        .focusSchedule, entityID,
        self.focusSchedulePayload(
          blockType: "buffer", date: entityID, version: later, start: 600, end: 660),
        schema: self.localMax, version: later)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: legacy), .applied)

      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID))
      XCTAssertEqual(shadow.baseVersion, later)
      XCTAssertEqual(shadow.payloadSchemaVersion, Int(self.newer))
      guard case .object(let object)? = JSONValue.parse(shadow.rawPayloadJSON) else {
        return XCTFail("retained higher-schema shadow must be an object")
      }
      XCTAssertEqual(object["future_context"], .string("survives legacy update"))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM focus_schedule WHERE date = ?", arguments: [entityID]),
        later)
    }
  }

  func testLegacyShadowAdvanceRollsBackWhenDispatchRejects() throws {
    try withDB { db in
      let entityID = "2026-04-04"
      let rejectedVersion = "1711234568001_0000_dec0000100000002"
      let future = try self.envelope(
        .focusSchedule, entityID,
        self.focusSchedulePayload(
          blockType: "buffer", date: entityID,
          topLevelExtras: ["future_context": .string("must remain aligned")]),
        schema: self.newer)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: future), .applied)

      let invalidLegacy = try self.envelope(
        .focusSchedule, entityID,
        self.focusSchedulePayload(
          blockType: "meeting", date: entityID, version: rejectedVersion),
        schema: self.localMax, version: rejectedVersion)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: self.registry(), envelope: invalidLegacy)
      ) { error in
        guard case .invalidPayload = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
      }

      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(
          db, entityType: EntityName.focusSchedule, entityID: entityID))
      XCTAssertEqual(shadow.baseVersion, self.vMid)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM focus_schedule WHERE date = ?", arguments: [entityID]),
        self.vMid)
    }
  }

  // MARK: - drain HOLD (retained, no attempt-count bump, would replay)

  /// Opaque recurrence JSON remains the genuine forward-compat lane: its known
  /// outer field is contract-valid, while the semantic FREQ is deferred by the
  /// applier and held without spending retry budget.
  func testForwardCompatDeferHeldByDrainWithoutAttemptBump() throws {
    try withDB { db in
      let eventID = "00000005-0000-7000-8000-000000000001"
      let env = try self.envelope(
        .calendarEvent, eventID,
        self.productionCalendarPayload(
          id: eventID, recurrence: #"{"FREQ":"FORTNIGHTLY"}"#),
        schema: self.newer)
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: env,
        reason: .schemaTooNew(remoteVersion: self.newer, localVersion: self.localMax))
      let before = try PendingInbox.getAllPending(db).first?.attemptCount

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry())

      XCTAssertEqual(summary.replayed, 0)
      XCTAssertEqual(summary.discarded, 0)
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1, "forward-compat envelope must stay parked, not drop")
      XCTAssertEqual(
        pending.first?.attemptCount, before, "a held schemaTooNew defer must not spend retry budget"
      )
      XCTAssertTrue(pending.first?.reason.contains("payload_schema_version") == true)
      // Never materialized while parked.
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [eventID]),
        0)
    }
  }

  // MARK: - batch non-abort

  /// An opaque semantic forward-compat defer returns `.deferred` (never throws),
  /// so an unrelated envelope immediately after it still lands.
  func testForwardCompatDeferDoesNotAbortBatch() throws {
    try withDB { db in
      let reg = self.registry()
      let eventID = "00000005-0000-7000-8000-000000000002"
      let poison = try self.envelope(
        .calendarEvent, eventID,
        self.productionCalendarPayload(
          id: eventID, recurrence: #"{"FREQ":"FORTNIGHTLY"}"#),
        schema: self.newer)
      let deferred = try Apply.applyEnvelope(db, registry: reg, envelope: poison)
      guard case .deferred = deferred else {
        return XCTFail("expected .deferred, got \(deferred)")
      }

      let healthy = try self.envelope(
        .focusSchedule, "2026-04-02",
        self.focusSchedulePayload(
          blockType: "buffer", date: "2026-04-02", start: 600, end: 630),
        schema: self.localMax)
      let applied = try Apply.applyEnvelope(db, registry: reg, envelope: healthy)
      guard case .applied = applied else {
        return XCTFail(
          "unrelated envelope after a forward-compat defer must still apply, got \(applied)")
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule WHERE date = ?", arguments: ["2026-04-02"]),
        1)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [eventID]),
        0)
    }
  }
}
