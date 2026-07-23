import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Sync conflict log — records merge outcomes for debugging and the Settings UI.
///
/// The `sync_conflict_log` table is local-only (never synced). One INSERT per
/// conflict, guarded by a natural-key dedupe so replays of the same envelope do
/// not duplicate rows. Conflicts are rare in single-user multi-device scenarios
/// but invaluable for debugging.
public enum ConflictLog {

  /// A sync conflict resolution record.
  public struct Entry: Sendable, Equatable {
    /// Row ID (autoincrement); 0 on input (assigned by DB), populated on read.
    public var id: Int64
    /// Canonical entity type name, or a diagnostic-only sentinel
    /// (e.g. `"sync_pending_inbox"`).
    public var entityType: String
    public var entityId: String
    public var winnerVersion: String
    public var loserVersion: String
    public var loserDeviceId: String
    /// The discarded snapshot (canonicalized JSON), if any.
    public var loserPayload: String?
    /// RFC 3339 timestamp when the conflict was resolved.
    public var resolvedAt: String
    /// The resolution strategy used — see ``ResolutionName``.
    public var resolutionType: String

    public init(
      id: Int64 = 0, entityType: String, entityId: String, winnerVersion: String,
      loserVersion: String, loserDeviceId: String, loserPayload: String?, resolvedAt: String,
      resolutionType: String
    ) {
      self.id = id
      self.entityType = entityType
      self.entityId = entityId
      self.winnerVersion = winnerVersion
      self.loserVersion = loserVersion
      self.loserDeviceId = loserDeviceId
      self.loserPayload = loserPayload
      self.resolvedAt = resolvedAt
      self.resolutionType = resolutionType
    }
  }

  /// PII-bearing JSON keys whose values are redacted before a loser payload is
  /// stored. Structure and non-text metadata (dates, flags, ids, HLC versions)
  /// stay intact so the conflict log remains useful for debugging.
  static let piiBearingKeys: Set<String> = [
    "title", "notes", "ai_notes", "description", "body", "location",
    "url", "person_name", "attendees_json", "attendees", "content", "summary",
    "before_json", "after_json",
  ]

  /// Record a sync conflict resolution.
  ///
  /// The `id` field is ignored; the database assigns an autoincrement row ID.
  /// `loserPayload`, if present, is passed through ``scrubLoserPayload(_:)``
  /// before insertion so user-authored text never lands verbatim.
  ///
  /// The INSERT is guarded by a `WHERE NOT EXISTS` on the natural-key tuple
  /// `(entity_type, entity_id, loser_version, loser_device_id, resolution_type,
  /// loser_payload)`. `loser_payload` is part of the key; the comparison is
  /// `IS NOT DISTINCT FROM` so two NULL payloads collapse, preserving
  /// idempotency for resolution types that carry no payload. A single tx
  /// emitting multiple conflict rows MUST set a payload that varies between
  /// them, or the rows collapse into one and silently hide every conflict after
  /// the first.
  public static func logConflict(_ db: Database, _ entry: Entry) throws {
    let scrubbed = entry.loserPayload.map(scrubLoserPayload)
    try db.execute(
      sql: """
        INSERT INTO sync_conflict_log
            (entity_type, entity_id, winner_version, loser_version,
             loser_device_id, loser_payload, resolved_at, resolution_type)
         SELECT ?, ?, ?, ?, ?, ?, ?, ?
         WHERE NOT EXISTS (
             SELECT 1 FROM sync_conflict_log
             WHERE entity_type = ?
               AND entity_id = ?
               AND loser_version = ?
               AND loser_device_id = ?
               AND resolution_type = ?
               AND loser_payload IS NOT DISTINCT FROM ?
         )
        """,
      arguments: [
        entry.entityType, entry.entityId, entry.winnerVersion, entry.loserVersion,
        entry.loserDeviceId, scrubbed, entry.resolvedAt, entry.resolutionType,
        // WHERE NOT EXISTS bindings (natural key)
        entry.entityType, entry.entityId, entry.loserVersion, entry.loserDeviceId,
        entry.resolutionType, scrubbed,
      ])
  }

  /// Replace the value of every PII-bearing JSON key with a placeholder while
  /// preserving the rest of the payload. Non-JSON payloads fall back to a
  /// generic suppression marker — the raw string is never stored.
  static func scrubLoserPayload(_ raw: String) -> String {
    guard var value = JSONValue.parse(raw) else {
      return "<non-json payload suppressed>"
    }
    scrubInPlace(&value)
    // Re-serialize via canonical JSON. The value just parsed from JSON and the
    // scrubber only replaces existing leaf values, so re-serialization is
    // infallible by construction.
    return (try? SyncCanonicalize.canonicalizeJSON(value)) ?? "<non-json payload suppressed>"
  }

  private static func scrubInPlace(_ value: inout JSONValue) {
    switch value {
    case .object(var map):
      for (k, v) in map {
        if piiBearingKeys.contains(k) {
          map[k] = .string("[REDACTED_PII]")
        } else {
          var child = v
          scrubInPlace(&child)
          map[k] = child
        }
      }
      value = .object(map)
    case .array(var items):
      for i in items.indices {
        scrubInPlace(&items[i])
      }
      value = .array(items)
    default:
      break
    }
  }

  /// Delete conflict log entries older than `retentionDays`. Returns the count.
  @discardableResult
  public static func gcConflicts(_ db: Database, retentionDays: UInt32) throws -> Int {
    try db.execute(
      sql: """
        DELETE FROM sync_conflict_log
         WHERE resolved_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)
        """,
      arguments: ["-\(retentionDays) days"])
    return db.changesCount
  }
}

/// Conflict-log + shadow-reap helpers for the LWW-loser and tombstone-loser
/// skip paths.
enum ApplyConflict {
  /// Record an LWW-loser conflict and return the matching `Skipped` apply
  /// result. Both the redirect-target branch and the normal-LWW branch share
  /// this exact shape: the same conflict-log row plus an identical
  /// "local newer than remote" message format.
  static func recordLwwConflictAndSkip(
    _ db: Database, entityType: String, entityId: String, localVersion: Hlc,
    envelope: SyncEnvelope, skipReason: String, applyTs: String
  ) throws -> ApplyResult {
    let localVersionStr = localVersion.description
    do {
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: entityType, entityId: entityId, winnerVersion: localVersionStr,
          loserVersion: envelope.version.description, loserDeviceId: envelope.deviceId,
          loserPayload: envelope.payload, resolvedAt: applyTs,
          resolutionType: ResolutionName.lww))
    } catch { throw ApplyError.lift(error) }
    // A Skipped envelope where the local version is strictly greater than any
    // shadow's base_version for the same (entity_type, entity_id) means that
    // shadow can never legally promote — reap it now.
    do {
      try PayloadShadow.removeShadowIfStrictlySuperseded(
        db, entityType: entityType, entityID: entityId, version: localVersionStr)
    } catch { throw ApplyError.lift(error) }
    return .skipped(reason: skipReason, winnerVersion: localVersion)
  }

  /// Companion to ``recordLwwConflictAndSkip`` for the non-LWW Skipped paths
  /// (tombstone-wins, delete-on-already-tombstoned). When the entity has a
  /// definite current version, every payload shadow older than it is obsolete.
  static func reapShadowForSkipped(
    _ db: Database, entityType: String, entityId: String, supersedingVersion: String
  ) throws {
    do {
      try PayloadShadow.removeShadowIfSuperseded(
        db, entityType: entityType, entityID: entityId, version: supersedingVersion)
    } catch { throw ApplyError.lift(error) }
  }
}
