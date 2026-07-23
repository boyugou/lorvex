import Foundation
import GRDB
import LorvexDomain
import LorvexSync
import Testing

@testable import LorvexCore

@Suite("Preference timezone sync invariants")
struct PreferenceTimezoneSyncTests {
  @Test("an inbound timezone delete is replaced by a dominating upsert")
  func inboundTimezoneDeleteCannotRemoveLogicalDayAuthority() async throws {
    let core = try makeInMemoryCore()
    _ = try await core.setPreference(
      key: PreferenceKeys.prefTimezone, value: "America/Los_Angeles")
    try core.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }

    let remoteVersion = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1_000) + 10_000,
      counter: 0,
      deviceSuffix: "abcdefabcdefabcd")
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "key": .string(PreferenceKeys.prefTimezone),
      "updated_at": .string("2026-07-21T20:00:00.000Z"),
      "value": .string(#""America/New_York""#),
      "version": .string(remoteVersion.description),
    ]))
    let envelope = SyncEnvelope(
      entityType: .preference,
      entityId: PreferenceKeys.prefTimezone,
      operation: .delete,
      version: remoteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload,
      deviceId: "remote-device")

    let report = try core.applyInbound([envelope], undecodable: 0)
    #expect(report.applied == 0)
    #expect(report.skipped == 1)
    #expect(report.appliedEntityTypes.contains(.preference))
    #expect(
      try await core.getPreference(key: PreferenceKeys.prefTimezone)
        == #""America/Los_Angeles""#)
    let tombstoneCount = try core.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_tombstones
          WHERE entity_type = 'preference' AND entity_id = ?
          """,
        arguments: [PreferenceKeys.prefTimezone]) ?? -1
    }
    #expect(tombstoneCount == 0)
    let successor = try #require(
      try core.pendingOutbound().first {
        $0.envelope.entityType == .preference
          && $0.envelope.entityId == PreferenceKeys.prefTimezone
      })
    #expect(successor.envelope.operation == .upsert)
    #expect(successor.envelope.version > remoteVersion)
  }

  @Test("a fresh peer recovers timezone from an inbound delete snapshot")
  func inboundTimezoneDeleteRecoversMissingRowFromSnapshot() async throws {
    let core = try makeInMemoryCore()
    let remoteVersion = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1_000) + 10_000,
      counter: 0,
      deviceSuffix: "abcdefabcdefabcd")
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "key": .string(PreferenceKeys.prefTimezone),
      "updated_at": .string("2026-07-21T20:00:00.000Z"),
      "value": .string(#""America/New_York""#),
      "version": .string(remoteVersion.description),
    ]))
    let envelope = SyncEnvelope(
      entityType: .preference,
      entityId: PreferenceKeys.prefTimezone,
      operation: .delete,
      version: remoteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload,
      deviceId: "remote-device")

    let report = try core.applyInbound([envelope], undecodable: 0)
    #expect(report.applied == 0)
    #expect(report.skipped == 1)
    #expect(report.appliedEntityTypes.contains(.preference))
    #expect(
      try await core.getPreference(key: PreferenceKeys.prefTimezone)
        == #""America/New_York""#)
    let successor = try #require(
      try core.pendingOutbound().first {
        $0.envelope.entityType == .preference
          && $0.envelope.entityId == PreferenceKeys.prefTimezone
      })
    #expect(successor.envelope.operation == .upsert)
    #expect(successor.envelope.version > remoteVersion)
  }

  @Test("equal-HLC timezone delete snapshots recover deterministically in either order")
  func equalTimezoneDeleteSnapshotsAreOrderIndependent() async throws {
    let remoteVersion = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1_000) + 10_000,
      counter: 0,
      deviceSuffix: "abcdefabcdefabcd")

    func envelope(value: String, updatedAt: String, device: String) throws -> SyncEnvelope {
      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "key": .string(PreferenceKeys.prefTimezone),
        "updated_at": .string(updatedAt),
        "value": .string(try SyncCanonicalize.canonicalizeJSON(.string(value))),
        "version": .string(remoteVersion.description),
      ]))
      return SyncEnvelope(
        entityType: .preference, entityId: PreferenceKeys.prefTimezone,
        operation: .delete, version: remoteVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: device)
    }

    let losAngeles = try envelope(
      value: "America/Los_Angeles", updatedAt: "2026-07-21T20:00:00.000Z",
      device: "remote-a")
    let newYork = try envelope(
      value: "America/New_York", updatedAt: "2026-07-21T19:00:00.000Z",
      device: "remote-b")

    var recovered: [String] = []
    for pair in [[losAngeles, newYork], [newYork, losAngeles]] {
      let core = try makeInMemoryCore()
      _ = try core.applyInbound(pair, undecodable: 0)
      recovered.append(
        try #require(
          try await core.getPreference(key: PreferenceKeys.prefTimezone)))
    }
    #expect(recovered[0] == recovered[1])
    #expect(recovered[0] == #""America/New_York""#)
  }

  @Test("a late old-zone reminder is re-anchored and re-emitted after inbound apply")
  func inboundOldZoneReminderConvergesToCurrentTimezone() async throws {
    let core = try makeInMemoryCore()
    _ = try await core.setPreference(key: PreferenceKeys.prefTimezone, value: "America/Los_Angeles")
    let task = try await core.createTask(title: "Timezone reminder", notes: "")
    let withReminder = try await core.addTaskReminder(
      taskID: task.id, reminderAt: "2026-07-22T16:00:00.000Z")
    let reminder = try #require(withReminder.reminders.first)
    let createdAt = try #require(reminder.createdAt)

    // The product timezone advances while a peer remains offline in Los
    // Angeles. Clear the already-accounted-for local mutations so the assertion
    // below observes only the convergence successor caused by the late peer.
    _ = try await core.setPreference(key: PreferenceKeys.prefTimezone, value: "America/New_York")
    try core.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }

    let remoteVersion = try Hlc(
      physicalMs: UInt64(Date().timeIntervalSince1970 * 1_000) + 10_000,
      counter: 0,
      deviceSuffix: "abcdefabcdefabcd")
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "cancelled_at": .null,
      "created_at": .string(createdAt),
      "dismissed_at": .null,
      "id": .string(reminder.id),
      "original_local_time": .string("09:00"),
      "original_tz": .string("America/Los_Angeles"),
      "reminder_at": .string("2026-07-22T16:00:00.000Z"),
      "task_id": .string(task.id),
      "version": .string(remoteVersion.description),
    ]))
    let envelope = SyncEnvelope(
      entityType: .taskReminder,
      entityId: reminder.id,
      operation: .upsert,
      version: remoteVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload,
      deviceId: "remote-device")

    let report = try core.applyInbound([envelope], undecodable: 0)
    #expect(report.applied == 1)
    #expect(report.appliedEntityTypes.contains(.taskReminder))

    let refreshed = try await core.loadTask(id: task.id)
    let repaired = try #require(refreshed.reminders.first { $0.id == reminder.id })
    #expect(repaired.reminderAt == "2026-07-22T13:00:00.000Z")
    #expect(repaired.originalLocalTime == "09:00")
    #expect(repaired.originalTz == "America/New_York")

    let successor = try #require(
      try core.pendingOutbound().first {
        $0.envelope.entityType == .taskReminder && $0.envelope.entityId == reminder.id
      })
    #expect(successor.envelope.version > remoteVersion)
    #expect(successor.envelope.operation == .upsert)
  }

  @Test("timezone re-anchor preserves an already-delivered device receipt")
  func timezoneReanchorDoesNotRefireDeliveredReminder() async throws {
    let core = try makeInMemoryCore()
    _ = try await core.setPreference(key: PreferenceKeys.prefTimezone, value: "America/Los_Angeles")
    let task = try await core.createTask(title: "Delivered reminder", notes: "")
    let updated = try await core.addTaskReminder(
      taskID: task.id, reminderAt: "2026-07-22T16:00:00.000Z")
    let reminder = try #require(updated.reminders.first)
    try core.write { db in
      try db.execute(
        sql: """
          INSERT INTO task_reminder_delivery_state
            (reminder_id, last_delivered_at, last_armed_at, delivery_state, updated_at)
          VALUES (?, ?, ?, 'delivered', ?)
          """,
        arguments: [
          reminder.id,
          "2026-07-22T16:00:00.000Z",
          "2026-07-22T15:00:00.000Z",
          "2026-07-22T16:00:00.000Z",
        ])
    }

    _ = try await core.setPreference(key: PreferenceKeys.prefTimezone, value: "America/New_York")

    let deliveryState = try core.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT delivery_state FROM task_reminder_delivery_state WHERE reminder_id = ?",
        arguments: [reminder.id])
    }
    #expect(deliveryState == "delivered")
  }
}
