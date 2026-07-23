import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// ai_changelog apply handler — the append-only audit-stream applier.
///
/// The changelog is append-only: entries are deduplicated by `id` (primary key)
/// rather than LWW-merged. Every peer-authored `delete` is rejected. Retention
/// uses a monotonic account-scoped frontier plus CloudKit physical deletion and
/// full reset deletes the generation zone, never a sync tombstone/delete
/// envelope. Conforms to ``EntityApplier`` so it registers in
/// an ``EntityApplierRegistry`` like every other per-entity applier.
///
/// The audit trail syncs across a user's devices under a BOUNDED contract:
/// each row is emitted once by the ordinary write path and converges by id-dedup
/// (`INSERT OR IGNORE`, no LWW). Ordinary full-resync skips it; candidate-zone
/// construction explicitly stages every retained row before retiring the prior
/// generation.
/// Before inserting, the account frontier rejects retired generations/keys and
/// queues a durable physical delete. A future generation is held until the
/// coordinator refreshes the frontier/policy; it is never interpreted under a
/// stale local policy.
public struct ChangelogApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityName.aiChangelog] }

  /// Cap on the post-scrub `summary` length stored in ai_changelog.
  static let maxSummaryLen = 4096
  /// Cap on `before_json` / `after_json` post-scrub size.
  static let maxBeforeAfterJsonLen = 64 * 1024
  /// Cap on the changelog `id` (envelope-supplied PK).
  static let maxChangelogIdLen = 64
  /// Cap on the changelog row's `target_entity_id` field.
  static let maxTargetEntityIdLen = 80

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let retained = try Self.applyChangelogEntry(
      db, entityId: envelope.entityId, payload: envelope.payload,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    return retained ? .applied : .upsertRejectedByRetention
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome {
    throw ApplyError.invalidOperation(
      entityType: EntityKind.aiChangelog.asString, operation: "delete")
  }

  /// Apply a changelog entry. Dedup by `id`: an existing entry is a silent
  /// no-op. Only `parseFully` proceeds — the append-only stream has no version
  /// column, so a forward-compat payload cannot be safely inserted with unknown
  /// fields truncated and later repaired by shadow promotion.
  ///
  /// A row outside the local retention horizon (see
  /// ``isBelowRetentionHorizon(_:timestamp:)``) is rejected BEFORE the insert, so
  /// a lagging peer cannot resurrect an entry this device has already GC'd. The
  /// `false` result is intentionally not a terminal silent drop: the applier
  /// durably queues an exact-zone CloudKit physical delete.
  @discardableResult
  static func applyChangelogEntry(
    _ db: Database, entityId: String, payload: String, payloadSchemaVersion: UInt32
  ) throws -> Bool {
    switch Capability.checkEnvelopeVersion(
      envelopePayloadVersion: payloadSchemaVersion,
      localMaxVersion: LorvexVersion.payloadSchemaVersion)
    {
    case .parseFully:
      break
    case .rejectInvalid, .parseForwardCompat, .deferToPendingInbox:
      throw ApplyError.invalidPayload(
        "ai_changelog payload_schema_version \(payloadSchemaVersion) "
          + "is not fully understood by local schema \(LorvexVersion.payloadSchemaVersion); "
          + "defer the changelog envelope until the audit row can be parsed without "
          + "truncating forward-compatible fields")
    }
    if entityId.utf8.count > maxChangelogIdLen {
      throw ApplyError.invalidPayload(
        "ai_changelog id exceeds \(maxChangelogIdLen)-char limit (got \(entityId.utf8.count) chars)"
      )
    }
    guard let parsed = JSONValue.parse(payload), let obj = ApplyJSON.object(parsed) else {
      throw ApplyError.invalidPayload("malformed sync payload JSON")
    }

    let timestampRaw = try requireTrimmedNonempty(obj, "timestamp")
    guard let timestamp = SyncTimestamp.parse(timestampRaw)?.asString else {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: timestamp must be an RFC 3339 UTC instant")
    }
    let retentionEpoch = try ApplyJSON.requiredInt64(
      obj, "retention_epoch", entity: "ai_changelog")
    guard retentionEpoch >= 0 else {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: retention_epoch must be nonnegative")
    }
    switch try AuditRetentionFrontier.classifyInboundAuditUpsert(
      db, entityId: entityId, retentionEpoch: retentionEpoch,
      timestamp: timestamp)
    {
    case .accept:
      break
    case .rejectAndPurge(let reason):
      try AuditRetentionFrontier.rejectInboundAuditAndQueuePurge(
        db, entityId: entityId, retentionEpoch: retentionEpoch, reason: reason)
      return false
    case .holdForFrontierRefresh(let requiredEpoch):
      throw ApplyError.deferForwardCompat(
        .auditRetentionFrontierRefresh(requiredEpoch: requiredEpoch))
    }
    let operation = try requireTrimmedNonempty(obj, "operation")
    let entityType = try requireTrimmedNonempty(obj, "entity_type")
    let targetEntityId = try ApplyJSON.optionalStr(obj, "entity_id", entity: "ai_changelog")
    let targetEntityIdScrubbed = targetEntityId.map(UnicodeHygiene.sanitizeUserText)
    if let t = targetEntityIdScrubbed, t.utf8.count > maxTargetEntityIdLen {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: entity_id exceeds \(maxTargetEntityIdLen)-char limit "
          + "(got \(t.utf8.count) chars after sanitization)")
    }
    let entityIds = try ApplyJSON.optionalStr(obj, "entity_ids", entity: "ai_changelog")
    let summary = try ApplyJSON.requiredStr(obj, "summary", entity: "ai_changelog")
    if summary.isEmpty {
      throw ApplyError.invalidPayload("ai_changelog payload: summary must not be empty")
    }
    let summaryScrubbed = UnicodeHygiene.sanitizeUserText(summary)
    if summaryScrubbed.utf8.count > maxSummaryLen {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: summary exceeds \(maxSummaryLen)-char limit "
          + "(got \(summaryScrubbed.utf8.count) chars after sanitization)")
    }
    let initiatedBy = try requireTrimmedNonempty(obj, "initiated_by")
    let mcpTool = try ApplyJSON.optionalStr(obj, "mcp_tool", entity: "ai_changelog")
    let sourceDeviceId = try ApplyJSON.optionalStr(obj, "source_device_id", entity: "ai_changelog")
    let beforeJson = try ApplyJSON.optionalStr(obj, "before_json", entity: "ai_changelog")
      .map(scrubJsonStringValues)
    let afterJson = try ApplyJSON.optionalStr(obj, "after_json", entity: "ai_changelog")
      .map(scrubJsonStringValues)
    if let b = beforeJson, b.utf8.count > maxBeforeAfterJsonLen {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: before_json exceeds \(maxBeforeAfterJsonLen)-byte limit "
          + "(got \(b.utf8.count) bytes after sanitization)")
    }
    if let a = afterJson, a.utf8.count > maxBeforeAfterJsonLen {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: after_json exceeds \(maxBeforeAfterJsonLen)-byte limit "
          + "(got \(a.utf8.count) bytes after sanitization)")
    }

    do {
      guard let accountIdentifier = try AuditRetentionFrontier.activeAccountIdentifier(db) else {
        throw AuditRetentionStateError.noActiveAccount
      }
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO ai_changelog
               (id, timestamp, operation, entity_type, entity_id,
                summary, initiated_by, mcp_tool, source_device_id,
                before_json, after_json, retention_epoch,
                retention_account_identifier)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          entityId, timestamp, operation, entityType, targetEntityIdScrubbed,
          summaryScrubbed, initiatedBy, mcpTool, sourceDeviceId,
          beforeJson, afterJson, retentionEpoch, accountIdentifier,
        ])
      // Populate the join table only when the INSERT actually landed.
      if db.changesCount > 0 {
        let ids: [String]
        do {
          ids = try ChangelogWrite.parseEntityIdsJson(entityIds)
        } catch {
          throw ApplyError.invalidPayload("ai_changelog payload: \(error)")
        }
        try ChangelogWrite.replaceChangelogEntities(db, changelogId: entityId, entityIds: ids)
      }
      try AuditRetentionFrontier.recordAcceptedInboundCloudPresence(
        db, entityId: entityId, retentionEpoch: retentionEpoch)
      return true
    } catch let e as ApplyError {
      throw e
    } catch { throw ApplyError.lift(error) }
  }

  /// Validate a string column against the schema's
  /// `length(value) > 0 AND value = trim(value)` CHECK contract.
  private static func requireTrimmedNonempty(_ obj: [String: JSONValue], _ key: String) throws
    -> String
  {
    let raw = try ApplyJSON.requiredStr(obj, key, entity: "ai_changelog")
    if raw.isEmpty {
      throw ApplyError.invalidPayload("ai_changelog payload: \(key) must not be empty")
    }
    if raw.trimmingCharacters(in: .whitespacesAndNewlines) != raw {
      throw ApplyError.invalidPayload(
        "ai_changelog payload: \(key) must not have leading/trailing whitespace")
    }
    return raw
  }

  /// Recursively scrub every string value through `sanitizeUserText`, then
  /// re-serialize. Object keys are schema-defined and not scrubbed.
  private static func scrubJsonStringValues(_ raw: String) throws -> String {
    guard let value = JSONValue.parse(raw) else {
      throw ApplyError.invalidPayload("ai_changelog payload: invalid before/after JSON")
    }
    let scrubbed = UnicodeHygiene.sanitizeUserTextInJSON(value)
    do {
      return try SyncCanonicalize.canonicalizeJSON(scrubbed)
    } catch { throw ApplyError.lift(error) }
  }
}
