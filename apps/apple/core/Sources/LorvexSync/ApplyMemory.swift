import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handlers for the KV-shaped aggregate roots `memory` and
/// `preference`. A memory row is identified by its opaque UUID `id`; the
/// human-authored `key` is a secondary UNIQUE natural key that feeds the
/// aggregate dedup merge. A preference row is keyed directly by its `key`.
///
/// `memory` scrubs + byte-clamps inbound `content` at the domain cap so a peer
/// cannot push an arbitrarily long jailbreak/prompt-injection payload through a
/// memory entry; truncation lands a `content_truncated` conflict-log row only
/// after the LWW-gated upsert actually wrote. `preference` filters local-only
/// keys at the apply boundary so an out-of-date peer cannot overwrite a per-device
/// value.
enum ApplyKVAggregate {

  // MARK: - memory

  static func applyMemoryUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    loserDeviceId: String, applyTs: String
  ) throws {
    let val = try ApplyJSON.parseObject(payload)
    // The row is identified by the opaque `entityId` (= `memories.id`); the
    // human-authored `key` title travels in the payload. Unicode hygiene: both
    // the key (a rendered section title) and the content (rendered to the
    // assistant at session start) have invisible controls stripped.
    let key = ApplyAggregate.scrub(try ApplyJSON.requiredStr(val, "key", entity: "memory"))
    let content = ApplyAggregate.scrub(try ApplyJSON.requiredStr(val, "content", entity: "memory"))
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "memory")

    let sentinel = Memory.memoryTruncationSentinel
    let contentBytes = Array(content.utf8)
    let cap = Memory.maxMemoryContentLength
    let clampedContent: String
    let truncated: Bool
    if contentBytes.count > cap {
      // Reserve room for the sentinel, then walk back to a UTF-8 char boundary.
      let sentinelBytes = Array(sentinel.utf8).count
      let budget = cap >= sentinelBytes ? cap - sentinelBytes : 0
      var cut = min(budget, contentBytes.count)
      while cut > 0 && !isUTF8CharBoundary(contentBytes, cut) {
        cut -= 1
      }
      let head = String(decoding: contentBytes[0..<cut], as: UTF8.self)
      clampedContent = head + sentinel
      truncated = true
    } else {
      clampedContent = content
      truncated = false
    }

    // Conflict is on the PK `id`, so an ordinary update keeps `id` (and thus the
    // CloudKit routing identity) stable and never rewrites `key` to a colliding
    // value on that path. A genuine two-device same-`key`/different-`id`
    // collision surfaces as a `UNIQUE(key)` violation and converges (min id
    // wins) rather than escaping as the batch-fatal ``ApplyError/db`` that would
    // wedge the inbound page.
    let sql = LwwUpsertSpec(
      table: "memories", columns: SyncEntityDescriptor.require(.memory).plainColumns,
      conflict: ["id"], tieBreak: tieBreak
    ).buildSQL()

    func runUpsert(_ db: Database, key: String) throws {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "key": key, "content": clampedContent, "updated_at": updatedAt,
          "version": version,
        ])
    }

    let outcome: CollisionMergeOutcome
    do {
      try runUpsert(db, key: key)
      outcome = CollisionMergeOutcome(
        incomingSurvived: db.changesCount > 0, mergeRan: false)
    } catch let dbError as DatabaseError where dbError.isUniqueConstraintViolation
    {
      // Stage the incoming beside the existing claimant under a synthetic
      // non-colliding key so it can land; the merge then collapses the
      // duplicates (min id wins, loser tombstoned + redirected) and restores the
      // real key to the winner.
      outcome = try ApplyMemoryMerge.insertMemoryByMergingCollision(
        db, entityId: entityId, key: key, version: version, applyTs: applyTs,
        originalError: dbError
      ) { db in
        try runUpsert(db, key: ApplyMemoryMerge.stagingKey(for: entityId))
      }
    } catch { throw ApplyError.lift(error) }

    // Post-upsert dedup tail: only when the upsert landed and the collision path
    // did not already merge. Defensive convergence pass.
    if outcome.incomingSurvived && !outcome.mergeRan {
      try ApplyMemoryMerge.mergeDuplicateMemories(
        db, justUpsertedId: entityId, version: version, applyTs: applyTs)
    }

    // Log the truncation conflict ONLY after the upsert actually landed (gated
    // on the incoming surviving as the live row). Firing before the version
    // compare would let a stale rejected envelope write a misleading "truncated"
    // row over an untouched live row.
    if truncated && outcome.incomingSurvived {
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: EntityName.memory, entityId: entityId, winnerVersion: version,
          loserVersion: version, loserDeviceId: loserDeviceId, loserPayload: payload,
          resolvedAt: applyTs, resolutionType: ResolutionName.contentTruncated))
    }
  }

  static func applyMemoryDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "memories", pkColumns: ["id"], pkValues: [entityId], incomingVersion: version)
  }

  /// True when `index` sits on a UTF-8 character boundary in `bytes`: index 0
  /// and `count` are boundaries; an
  /// interior index is a boundary iff the byte is not a continuation byte
  /// (`0b10xxxxxx`).
  private static func isUTF8CharBoundary(_ bytes: [UInt8], _ index: Int) -> Bool {
    if index == 0 || index == bytes.count { return true }
    if index < 0 || index > bytes.count { return false }
    return (bytes[index] & 0xC0) != 0x80
  }

  // MARK: - preference

  static func applyPreferenceUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak
  ) throws {
    if PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId) {
      return
    }
    let val = try ApplyJSON.parseObject(payload)
    guard let valueNode = val["value"] else {
      throw ApplyError.invalidPayload("preference payload: value is required")
    }
    // Validate the per-key value semantics before persistence. This is the peer
    // counterpart of the local/import write gate: a malformed timezone,
    // working-hours object, or boolean must be dropped as a poison envelope,
    // never stored where it can brick every later workflow read.
    let normalizedValue: JSONValue
    switch PreferenceValueContract.normalize(key: entityId, value: valueNode) {
    case .success(let value): normalizedValue = value
    case .failure(let error):
      throw ApplyError.invalidPayload("preference payload: \(error.description)")
    }
    // The preference `value` column stores the normalized JSON node; route
    // through canonicalizeJSON so the bound bytes are stable (matches the
    // store-side preference write path).
    let valueJSON: String
    do {
      valueJSON = try SyncCanonicalize.canonicalizeJSON(normalizedValue)
    } catch { throw ApplyError.lift(error) }
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "preference")

    let sql = LwwUpsertSpec(
      table: "preferences", columns: SyncEntityDescriptor.require(.preference).plainColumns,
      conflict: ["key"], tieBreak: tieBreak
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "key": entityId, "value": valueJSON, "updated_at": updatedAt, "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
  }

  static func applyPreferenceDelete(_ db: Database, entityId: String, version: String) throws
    -> EntityApplyOutcome
  {
    if PreferenceKeys.isExcludedFromPreferenceEntitySync(entityId) {
      // An excluded preference never uses the ordinary entity stream; a crafted
      // delete must not mint a tombstone over a surviving local row or dedicated
      // control-plane value. Return the typed permanent skip.
      return .deleteSkippedLocalOnly
    }
    try ApplyLww.lwwGatedDelete(
      db, table: "preferences", pkColumns: ["key"], pkValues: [entityId], incomingVersion: version)
    return .applied
  }

}

// MARK: - EntityApplier conformances

/// Apply handler for the `memory` aggregate (UUID `id` primary key; `key` is
/// the secondary UNIQUE natural key). Threads the envelope's `deviceId` for
/// the truncation conflict-log loser attribution.
public struct MemoryApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.memory] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyKVAggregate.applyMemoryUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, loserDeviceId: envelope.deviceId,
      applyTs: applyTs)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyKVAggregate.applyMemoryDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

/// Apply handler for the `preference` aggregate (KV PK = `key`).
public struct PreferenceApplier: EntityApplier {
  public init() {}
  public var handledEntityTypes: [String] { [EntityName.preference] }
  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyKVAggregate.applyPreferenceUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak)
    return .applied
  }
  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    try ApplyKVAggregate.applyPreferenceDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
  }
}
