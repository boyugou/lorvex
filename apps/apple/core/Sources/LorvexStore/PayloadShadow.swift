import Foundation
import GRDB
import LorvexDomain

/// Slim error type for payload-shadow operations.
///
/// The shadow CRUD/merge helpers run before the disk-full classifier sees a
/// database error, so the enum stays minimal. The `.sql` case carries the
/// underlying GRDB error unclassified; the higher layers re-run the disk-full
/// classifier when converting to `StoreError`.
public enum PayloadError: Error, Sendable {
  /// A database error propagated from GRDB.
  case sql(Error)
  /// A caller-supplied value failed validation (size cap, malformed HLC).
  case validation(String)
  /// An internal invariant was violated (unknown `EntityKind` in a stored row).
  case invariant(String)
  /// A serialization or deserialization error.
  case serialization(String)
}

extension PayloadError: CustomStringConvertible {
  /// Stable diagnostic wording; keep it byte-identical. The corruption test
  /// asserts on the embedded `validation error: …` substring, so this wording
  /// must not drift.
  public var description: String {
    switch self {
    case .sql(let e): return "database error: \(e)"
    case .validation(let m): return "validation error: \(m)"
    case .invariant(let m): return "invariant violation: \(m)"
    case .serialization(let m): return "serialization error: \(m)"
    }
  }
}

/// Forward-compat payload shadow subsystem.
///
/// The shadow row preserves unknown JSON keys across LWW conflicts and re-emits
/// so a peer running a newer schema can carry forward-compat fields through a
/// network of older peers without losing them. This enum hosts the CRUD
/// primitives, the size guard, the owned-key allowlist, and the merge / redirect
/// logic. Lives in `LorvexStore` rather than `LorvexSync` because every
/// dependency (EntityKind, Hlc, JSONValue, canonicalizeJSON, error_logs) is a
/// store-or-domain concern, below both the store and sync surfaces.
public enum PayloadShadow {
  /// Maximum allowed byte size for a `raw_payload_json` written to
  /// `sync_payload_shadow`. Re-exports the canonical
  /// `LorvexDomain.StorageSchema.maxPayloadBytes` so the canonicalize gate, the
  /// shadow writer, and the pending-inbox staging path share one source of
  /// truth.
  public static let maxRawPayloadJSONBytes: Int = StorageSchema.maxPayloadBytes

  /// A `sync_payload_shadow` row.
  public struct Row: Sendable, Equatable {
    public var entityType: EntityKind
    public var entityID: String
    public var baseVersion: String
    public var payloadSchemaVersion: Int
    public var rawPayloadJSON: String
    /// Original device_id from the envelope that preserved this shadow.
    /// Replayed verbatim by promotion so any conflict_log entry written during
    /// promotion attributes truncation / LWW losses to the real peer. Empty
    /// string for rows that pre-date the column or for import archives produced
    /// before this field was tracked.
    public var sourceDeviceID: String
    public var updatedAt: String

    public init(
      entityType: EntityKind, entityID: String, baseVersion: String,
      payloadSchemaVersion: Int, rawPayloadJSON: String, sourceDeviceID: String,
      updatedAt: String
    ) {
      self.entityType = entityType
      self.entityID = entityID
      self.baseVersion = baseVersion
      self.payloadSchemaVersion = payloadSchemaVersion
      self.rawPayloadJSON = rawPayloadJSON
      self.sourceDeviceID = sourceDeviceID
      self.updatedAt = updatedAt
    }
  }

  // MARK: - Shared validators / parsers

  /// Shared size validator for `raw_payload_json`. Every writer entry —
  /// including the import path's `restoreShadow` — enforces the same cap. The
  /// error wording is a stable contract; keep it byte-identical.
  static func validateRawPayloadSize(
    entityType: String, entityID: String, rawPayloadJSON: String
  ) throws {
    let len = rawPayloadJSON.utf8.count
    if len > maxRawPayloadJSONBytes {
      throw PayloadError.validation(
        "sync_payload_shadow raw_payload_json for \(entityType):\(entityID) "
          + "is \(len) bytes; exceeds maximum of \(maxRawPayloadJSONBytes) bytes")
    }
  }

  static func parseHLC(_ version: String, context: String) throws -> Hlc {
    do {
      return try Hlc.parseCanonical(version)
    } catch {
      throw PayloadError.validation("invalid HLC in \(context): \(version)")
    }
  }

  /// Convert the SQLite-backed schema version to the wire's exact UInt32
  /// domain. The table CHECK prevents invalid new writes; this read boundary
  /// keeps legacy/manual corruption from being silently clamped into a different
  /// protocol version by an outbound or generation snapshot.
  public static func requireWirePayloadSchemaVersion(
    _ row: Row, context: String
  ) throws -> UInt32 {
    guard
      let version = UInt32(exactly: row.payloadSchemaVersion),
      version >= 1
    else {
      throw PayloadError.invariant(
        "invalid payload_schema_version \(row.payloadSchemaVersion) in \(context) for "
          + "\(row.entityType.asString):\(row.entityID)")
    }
    return version
  }

  /// Parse a SQLite-stored `entity_type` column at the read boundary, surfacing
  /// an unknown value as a typed `.invariant` that preserves the offending
  /// string for diagnostics.
  static func parseEntityKindFromRow(_ value: String) throws -> EntityKind {
    guard let kind = EntityKind.parse(value) else {
      throw PayloadError.invariant(
        "sync_payload_shadow.entity_type contains unknown entity kind "
          + "\(jsonStringLiteral(value)): unknown entity kind: \(value)")
    }
    return kind
  }

  // MARK: - CRUD

  /// Upsert a shadow row, persisting only the unknown-keys diff.
  ///
  /// The full `rawPayloadJSON` arriving here holds every known schema field plus
  /// any forward-compat unknown keys the peer shipped. The re-emit merge path
  /// overwrites every known key from the live local payload, so the shadow's
  /// copy of those known keys is never read; stripping them halves long-term
  /// storage growth. A parse failure (non-object payload) falls back to
  /// persisting the raw form verbatim — the apply pipeline already enforced
  /// canonical shape upstream. The LWW gate `excluded.base_version >
  /// sync_payload_shadow.base_version` keeps the newest base.
  public static func upsertShadow(
    _ db: Database, entityType: String, entityID: String, baseVersion: String,
    payloadSchemaVersion: Int, rawPayloadJSON: String, sourceDeviceID: String
  ) throws {
    let trimmed = stripKnownKeysForShadow(entityType: entityType, rawPayloadJSON: rawPayloadJSON)
    let payloadForDB = trimmed ?? rawPayloadJSON
    try validateRawPayloadSize(
      entityType: entityType, entityID: entityID, rawPayloadJSON: payloadForDB)
    do {
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow (
              entity_type, entity_id, base_version, payload_schema_version,
              raw_payload_json, source_device_id, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
           ON CONFLICT(entity_type, entity_id) DO UPDATE SET
              base_version = excluded.base_version,
              payload_schema_version = excluded.payload_schema_version,
              raw_payload_json = excluded.raw_payload_json,
              source_device_id = excluded.source_device_id,
              updated_at = excluded.updated_at
           WHERE excluded.base_version > sync_payload_shadow.base_version
          """,
        arguments: [
          entityType, entityID, baseVersion, payloadSchemaVersion, payloadForDB,
          sourceDeviceID,
        ])
    } catch { throw PayloadError.sql(error) }
  }

  /// Parse `rawPayloadJSON` as a JSON object and remove every key the local
  /// schema owns, returning the trimmed re-serialized form. Returns `nil` for
  /// any input that doesn't parse as a JSON object, for an entity type with no
  /// owned keys, or for a payload that had nothing to strip — in all three the
  /// caller persists the raw form verbatim (preserving upstream canonical
  /// spacing).
  static func stripKnownKeysForShadow(
    entityType: String, rawPayloadJSON: String
  ) -> String? {
    guard let parsed = JSONValue.parse(rawPayloadJSON), case .object(var object) = parsed else {
      return nil
    }
    let owned = ownedKeysForEntity(entityType)
    if owned.isEmpty {
      return nil
    }
    var trimmedAny = false
    for key in owned where object[key] != nil {
      object[key] = nil
      trimmedAny = true
    }
    if !trimmedAny {
      return nil
    }
    return try? canonicalizeJSON(.object(object))
  }

  public static func getShadow(
    _ db: Database, entityType: String, entityID: String
  ) throws -> Row? {
    do {
      guard
        let row = try GRDB.Row.fetchOne(
          db,
          sql: """
            SELECT entity_type, entity_id, base_version, payload_schema_version,
                   raw_payload_json, source_device_id, updated_at
                FROM sync_payload_shadow
                WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [entityType, entityID])
      else { return nil }
      return try rowToShadow(row)
    } catch let e as PayloadError {
      throw e
    } catch { throw PayloadError.sql(error) }
  }

  public static func listShadows(_ db: Database) throws -> [Row] {
    do {
      let rows = try GRDB.Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id, base_version, payload_schema_version,
                 raw_payload_json, source_device_id, updated_at
          FROM sync_payload_shadow
          ORDER BY entity_type, entity_id
          """)
      return try rows.map(rowToShadow)
    } catch let e as PayloadError {
      throw e
    } catch { throw PayloadError.sql(error) }
  }

  private static func rowToShadow(_ row: GRDB.Row) throws -> Row {
    Row(
      entityType: try parseEntityKindFromRow(row["entity_type"]),
      entityID: row["entity_id"],
      baseVersion: row["base_version"],
      payloadSchemaVersion: row["payload_schema_version"],
      rawPayloadJSON: row["raw_payload_json"],
      sourceDeviceID: row["source_device_id"],
      updatedAt: row["updated_at"])
  }

  /// Restore (import path) a shadow row.
  ///
  /// The LWW predicate is `>=` rather than `>` so aggregate/redirect provenance
  /// selection can relocate the chosen complete shadow onto the canonical
  /// identity even when its `base_version` ties a shadow already stored there.
  /// Equal-HLC shadow objects are never key-unioned; the selected whole snapshot
  /// replaces the target. The same size cap as `upsertShadow` is enforced at the
  /// import boundary.
  public static func restoreShadow(_ db: Database, row: Row) throws {
    try validateRawPayloadSize(
      entityType: row.entityType.asString, entityID: row.entityID,
      rawPayloadJSON: row.rawPayloadJSON)
    do {
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow (
              entity_type, entity_id, base_version, payload_schema_version,
              raw_payload_json, source_device_id, updated_at
           ) VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(entity_type, entity_id) DO UPDATE SET
              base_version = excluded.base_version,
              payload_schema_version = excluded.payload_schema_version,
              raw_payload_json = excluded.raw_payload_json,
              source_device_id = excluded.source_device_id,
              updated_at = excluded.updated_at
           WHERE excluded.base_version >= sync_payload_shadow.base_version
          """,
        arguments: [
          row.entityType.asString, row.entityID, row.baseVersion,
          row.payloadSchemaVersion, row.rawPayloadJSON, row.sourceDeviceID,
          row.updatedAt,
        ])
    } catch { throw PayloadError.sql(error) }
  }

  /// Advance an existing shadow's `base_version` to `newBaseVersion` when it
  /// strictly supersedes the stored one (canonical HLC strings order lexically,
  /// so the SQL `>` gate is a valid HLC comparison — matching ``upsertShadow``).
  ///
  /// A local upsert that merges a shadow into its outbound payload leaves the
  /// live row at the new version while the shadow keeps the older base it was
  /// stashed at. Promotion at the next schema upgrade would then see
  /// `live > base`, treat the shadow as obsolete, and reap its forward-compat
  /// keys before they could fill the now-known columns. Bumping the base to the
  /// row's new version keeps `live == base` so promotion takes the equal-version
  /// fill branch. The `raw_payload_json` (the preserved unknown keys) is
  /// untouched; only the version bookkeeping moves.
  public static func advanceShadowBaseVersion(
    _ db: Database, entityType: String, entityID: String, newBaseVersion: String
  ) throws {
    do {
      try db.execute(
        sql: """
          UPDATE sync_payload_shadow
          SET base_version = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          WHERE entity_type = ? AND entity_id = ? AND ? > base_version
          """,
        arguments: [newBaseVersion, entityType, entityID, newBaseVersion])
    } catch { throw PayloadError.sql(error) }
  }

  /// Prepare an admitted upsert whose payload schema is understood by this
  /// runtime. Returns `true` when a shadow from a HIGHER schema was retained.
  ///
  /// A payload that predates the shadow cannot author an intentional clear for
  /// those future fields. Preserve the unknown-key snapshot and advance its base
  /// to the admitted row version so a later promotion/outbound snapshot composes
  /// it with the matching known row. When the incoming schema understands the
  /// shadow, ordinary HLC supersession may reap it.
  ///
  /// The compare-and-swap is defense in depth around the write-transaction
  /// serialization contract. Any provenance mismatch throws so the enclosing
  /// per-envelope savepoint rolls both the shadow bookkeeping and domain write
  /// back together.
  @discardableResult
  public static func prepareForKnownSchemaUpsert(
    _ db: Database, entityType: String, entityID: String,
    incomingPayloadSchemaVersion: Int, incomingVersion: String
  ) throws -> Bool {
    guard let existing = try getShadow(db, entityType: entityType, entityID: entityID) else {
      return false
    }
    guard existing.payloadSchemaVersion > incomingPayloadSchemaVersion else {
      try removeShadowIfSuperseded(
        db, entityType: entityType, entityID: entityID, version: incomingVersion)
      return false
    }

    let shadowHlc = try parseHLC(
      existing.baseVersion, context: "higher-schema payload shadow base_version")
    let incomingHlc = try parseHLC(
      incomingVersion, context: "admitted legacy payload version")
    guard incomingHlc >= shadowHlc else {
      throw PayloadError.invariant(
        "admitted legacy upsert precedes its higher-schema payload shadow: "
          + "\(entityType):\(entityID) incoming=\(incomingVersion) "
          + "shadow=\(existing.baseVersion)")
    }
    guard incomingHlc > shadowHlc else { return true }

    do {
      try db.execute(
        sql: """
          UPDATE sync_payload_shadow
          SET base_version = ?, updated_at = ?
          WHERE entity_type = ? AND entity_id = ?
            AND base_version = ? AND payload_schema_version = ?
          """,
        arguments: [
          incomingVersion, SyncTimestampFormat.syncTimestampNow(), entityType, entityID,
          existing.baseVersion, existing.payloadSchemaVersion,
        ])
      guard db.changesCount == 1 else {
        throw PayloadError.invariant(
          "higher-schema payload shadow changed during legacy upsert preparation: "
            + "\(entityType):\(entityID)")
      }
    } catch let error as PayloadError {
      throw error
    } catch {
      throw PayloadError.sql(error)
    }
    return true
  }

  public static func removeShadow(
    _ db: Database, entityType: String, entityID: String
  ) throws {
    do {
      try db.execute(
        sql: "DELETE FROM sync_payload_shadow WHERE entity_type = ? AND entity_id = ?",
        arguments: [entityType, entityID])
    } catch { throw PayloadError.sql(error) }
  }

  /// Remove the shadow row if a candidate envelope version supersedes it.
  ///
  /// A corrupted persisted `base_version` (old data, manual DB edit, future
  /// schema bug) must not fail the apply path — one bad shadow row would block
  /// every subsequent envelope for that entity. We can't compare a malformed
  /// version against the candidate, so we log-and-delete it so the candidate can
  /// proceed.
  public static func removeShadowIfSuperseded(
    _ db: Database, entityType: String, entityID: String, version: String
  ) throws {
    try removeShadowIfSuperseded(
      db, entityType: entityType, entityID: entityID, version: version,
      requireStrictlyGreater: false)
  }

  /// Remove the shadow row only if a candidate envelope version strictly
  /// supersedes it. LWW-loser reaping needs this form: an equal live winner
  /// still leaves an equal-version forward-compat shadow eligible for later
  /// promotion once the app understands the payload schema.
  public static func removeShadowIfStrictlySuperseded(
    _ db: Database, entityType: String, entityID: String, version: String
  ) throws {
    try removeShadowIfSuperseded(
      db, entityType: entityType, entityID: entityID, version: version,
      requireStrictlyGreater: true)
  }

  private static func removeShadowIfSuperseded(
    _ db: Database, entityType: String, entityID: String, version: String,
    requireStrictlyGreater: Bool
  ) throws {
    guard let existing = try getShadow(db, entityType: entityType, entityID: entityID) else {
      return
    }
    let shadowVersion: Hlc
    do {
      shadowVersion = try parseHLC(existing.baseVersion, context: "payload shadow base_version")
    } catch let parseErr {
      let errText = (parseErr as? PayloadError)?.description ?? "\(parseErr)"
      ErrorLog.appendBestEffort(
        db, source: "store.payload_shadow.corrupted_base_version",
        message: "corrupted base_version on persisted payload shadow",
        details:
          "entity_type=\(entityType) entity_id=\(entityID) base_version=\(existing.baseVersion) "
          + "source_device_id=\(existing.sourceDeviceID) error=\(errText)",
        level: "warn")
      try removeShadow(db, entityType: entityType, entityID: entityID)
      return
    }
    let candidate = try parseHLC(version, context: "payload shadow candidate version")
    let shouldRemove =
      requireStrictlyGreater ? candidate > shadowVersion : candidate >= shadowVersion
    if shouldRemove {
      try removeShadow(db, entityType: entityType, entityID: entityID)
    }
  }

  // MARK: - Small JSON helper

  /// A debug-quoted string literal (`"value"`). Used in the unknown-entity-kind
  /// invariant message.
  static func jsonStringLiteral(_ value: String) -> String {
    if let encoded = try? canonicalizeJSON(.string(value)) {
      return encoded
    }
    return "\"\(value)\""
  }
}
