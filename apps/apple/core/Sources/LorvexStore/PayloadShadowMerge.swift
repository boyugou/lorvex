import Foundation
import GRDB
import LorvexDomain

extension PayloadShadow {

  // MARK: - parse helper

  /// Parse a string as a JSON object map; reject non-object payloads with a
  /// typed `.serialization` error whose wording is `"<context> must be a JSON
  /// object"`.
  static func parseJSONObject(
    _ raw: String, context: String
  ) throws -> [String: JSONValue] {
    guard let value = JSONValue.parse(raw) else {
      throw PayloadError.serialization("\(context) must be a JSON object")
    }
    guard case .object(let map) = value else {
      throw PayloadError.serialization("\(context) must be a JSON object")
    }
    return map
  }

  // MARK: - merge finalize

  /// Shared finalize step: overlays the known payload onto the shadow's
  /// forward-compat keys and gates the merged result against the size cap.
  ///
  public static func mergePayloadWithShadowAfterLookup(
    _ db: Database, entityType: String, entityID: String, knownPayload: JSONValue,
    shadow: Row
  ) throws -> JSONValue {
    var mergedObj = try parseJSONObject(
      shadow.rawPayloadJSON, context: "sync payload shadow raw_payload_json")
    guard case .object(let knownObj) = knownPayload else {
      let kind: String
      switch knownPayload {
      case .null: kind = "null"
      case .bool: kind = "bool"
      case .int, .uint, .double: kind = "number"
      case .string: kind = "string"
      case .array: kind = "array"
      case .object: kind = "object"
      }
      throw PayloadError.validation(
        "merge_payload_with_shadow expects an object payload for "
          + "\(entityType):\(entityID) (got \(kind))")
    }

    for (key, value) in knownObj {
      mergedObj[key] = value
    }
    for key in ownedKeysForEntity(entityType) where knownObj[key] == nil {
      mergedObj[key] = nil
    }

    let merged = JSONValue.object(mergedObj)

    // Bound the merged result before it propagates into outbox enqueue /
    // re-canonicalization. The serialize-then-measure shape matches the three
    // writers that gate against this cap. Measured against the canonical
    // (sorted-key) serialization, which is what the next canonicalize pass
    // would actually emit.
    let mergedSerialized = try canonicalizeJSON(merged)
    if mergedSerialized.utf8.count > maxRawPayloadJSONBytes {
      throw PayloadError.validation(
        "merge_payload_with_shadow merged payload for \(entityType):\(entityID) "
          + "is \(mergedSerialized.utf8.count) bytes; exceeds maximum of "
          + "\(maxRawPayloadJSONBytes) bytes "
          + "(forward-compat unknown keys + known payload exceeded the cap)")
    }
    return merged
  }

  /// Promotion-specific shadow-authoritative merge. The stored shadow contains
  /// only keys that were unknown when it was written. Once an upgraded build
  /// owns those keys, overlay their exact preserved values over the live
  /// snapshot — including over migration defaults/non-NULL placeholders.
  /// Promotion only dispatches on equal base/live versions, proving no later
  /// local edit exists to clobber.
  ///
  /// Distinct from `mergePayloadWithShadowAfterLookup`, which is live-WINS and
  /// nulls-out owned keys absent from live: correct for outbound re-emit, but on
  /// the promotion path it would overwrite the truncated forward-compat value
  /// with the live NULL and then the shadow is reaped — destroying the exact
  /// value promotion exists to restore.
  public static func mergePayloadForPromotion(
    _ db: Database, entityType: String, entityID: String, knownPayload: JSONValue, shadow: Row
  ) throws -> JSONValue {
    let shadowObj = try parseJSONObject(
      shadow.rawPayloadJSON, context: "promote payload shadow raw_payload_json")
    guard case .object(let knownObj) = knownPayload else {
      throw PayloadError.validation(
        "merge_payload_for_promotion expects an object payload for \(entityType):\(entityID)")
    }
    var mergedObj = knownObj
    for (key, value) in shadowObj { mergedObj[key] = value }

    let merged = JSONValue.object(mergedObj)
    let mergedSerialized = try canonicalizeJSON(merged)
    if mergedSerialized.utf8.count > maxRawPayloadJSONBytes {
      throw PayloadError.validation(
        "merge_payload_for_promotion merged payload for \(entityType):\(entityID) "
          + "is \(mergedSerialized.utf8.count) bytes; exceeds maximum of "
          + "\(maxRawPayloadJSONBytes) bytes")
    }
    return merged
  }

  // MARK: - merge entry points

  /// Per-row unindexed overlay path: reconstruct the live payload for a single
  /// `(entityType, entityID)` by overlaying the locally-known fields onto the
  /// shadow's preserved forward-compat keys.
  public static func mergePayloadWithShadow(
    _ db: Database, entityType: String, entityID: String, knownPayload: JSONValue
  ) throws -> JSONValue {
    try mergePayloadWithShadowReporting(
      db, entityType: entityType, entityID: entityID, knownPayload: knownPayload
    ).payload
  }

  /// ``mergePayloadWithShadow`` that also reports which shadow (if any) actually
  /// contributed forward-compat keys to the merged payload.
  ///
  /// `mergedShadow` is nil when no shadow row exists. The outbound enqueue path
  /// uses the reported shadow to (1) stamp the re-emitted
  /// envelope at `max(localPayloadSchemaVersion, shadow.payloadSchemaVersion)` so
  /// same-schema peers take the forward-compat path and re-stash the unknown keys
  /// instead of dropping them (and reaping their own shadow), and (2) advance the
  /// shadow's `base_version` to the new row version so a later local upgrade
  /// promotes the keys instead of reaping the shadow as obsolete.
  public static func mergePayloadWithShadowReporting(
    _ db: Database, entityType: String, entityID: String, knownPayload: JSONValue
  ) throws -> (payload: JSONValue, mergedShadow: Row?) {
    guard let shadow = try getShadow(db, entityType: entityType, entityID: entityID) else {
      return (knownPayload, nil)
    }
    let payload = try mergePayloadWithShadowAfterLookup(
      db, entityType: entityType, entityID: entityID, knownPayload: knownPayload,
      shadow: shadow)
    return (payload, shadow)
  }

  // MARK: - redirect consolidation

  /// Move the content-newer shadow row onto the redirect target.
  ///
  /// Redirects are same-type by contract. The merge runs a SAVEPOINT-protected
  /// read-select-write driven by an HLC-ordered LWW choice with an explicit CAS
  /// re-check on the winner's `base_version` to defeat a concurrent winner
  /// update.
  public static func mergeShadowIntoRedirect(
    _ db: Database, fromEntityType: String, fromEntityID: String,
    toEntityType: String, toEntityID: String
  ) throws {
    guard fromEntityType == toEntityType else {
      throw PayloadError.invariant(
        "merge_shadow_into_redirect requires a same-type identity alias")
    }
    guard let loser = try getShadow(db, entityType: fromEntityType, entityID: fromEntityID) else {
      return
    }

    try StoreTransactions.withSavepoint(db, "merge_shadow_redirect") { db in
      let winner = try getShadow(db, entityType: toEntityType, entityID: toEntityID)
      let winnerBaseVersionBefore = winner?.baseVersion
      let selected: Row
      if let w = winner {
        selected = try selectShadowRow(target: w, source: loser)
      } else {
        guard let toKind = EntityKind.parse(toEntityType) else {
          throw PayloadError.invariant(
            "merge_shadow_into_redirect: redirect target entity_type "
              + "\(jsonStringLiteral(toEntityType)) is not a known EntityKind")
        }
        selected = Row(
          entityType: toKind, entityID: toEntityID, baseVersion: loser.baseVersion,
          payloadSchemaVersion: loser.payloadSchemaVersion,
          rawPayloadJSON: loser.rawPayloadJSON, sourceDeviceID: loser.sourceDeviceID,
          updatedAt: loser.updatedAt)
      }

      let winnerBaseVersionAfter: String?
      do {
        winnerBaseVersionAfter = try String.fetchOne(
          db,
          sql: """
            SELECT base_version FROM sync_payload_shadow
            WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [toEntityType, toEntityID])
      } catch { throw PayloadError.sql(error) }

      if winnerBaseVersionBefore != winnerBaseVersionAfter {
        throw PayloadError.validation(
          "merge_shadow_into_redirect: concurrent winner update on "
            + "\(toEntityType):\(toEntityID) (base_version changed from "
            + "\(optDebug(winnerBaseVersionBefore)) to \(optDebug(winnerBaseVersionAfter))); "
            + "merge aborted, loser shadow preserved for retry")
      }

      try restoreShadow(db, row: selected)
      try removeShadow(db, entityType: fromEntityType, entityID: fromEntityID)
    }
  }

  /// HLC-ordered whole-row choice for two shadows targeting the same redirect
  /// terminus. The newer content wins; an equal HLC keeps the canonical target
  /// identity's row. Never union keys: key absence can be an intentional clear.
  static func selectShadowRow(target: Row, source: Row) throws -> Row {
    let winnerVersion = try parseHLC(
      target.baseVersion, context: "target payload shadow base_version")
    let loserVersion = try parseHLC(
      source.baseVersion, context: "source payload shadow base_version")
    var selected: Row
    if loserVersion > winnerVersion {
      selected = source
    } else {
      selected = target
    }
    selected.entityType = target.entityType
    selected.entityID = target.entityID
    selected.updatedAt = SyncTimestampFormat.syncTimestampNow()
    return selected
  }

  /// Render an optional string in debug style: `None` or `Some("v")`.
  private static func optDebug(_ value: String?) -> String {
    guard let v = value else { return "None" }
    return "Some(\(jsonStringLiteral(v)))"
  }
}
