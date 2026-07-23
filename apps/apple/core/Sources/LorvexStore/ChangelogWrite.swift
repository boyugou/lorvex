import Foundation
import GRDB
import LorvexDomain

/// The `ai_changelog` row INSERT, the `before_json` / `after_json` size cap,
/// the `summary` control-character / length sanitizer, and the
/// `ai_changelog_entities` per-row entity-id registry — the WRITE side of the
/// audit trail. The read side lives in ``AiChangelogQueryRepo``.
public enum ChangelogWrite {

  /// Per-snapshot cap for `before_json` / `after_json` payloads, in bytes.
  /// Over-budget payloads become a valid JSON sentinel containing a bounded
  /// preview and the original byte count. Keeping the stored value parseable is
  /// part of the sync payload contract; a raw prefix plus `…` is not JSON.
  public static let maxChangelogStateJsonBytes = 4000

  /// Maximum character count for an `ai_changelog.summary` cell after
  /// sanitization.
  public static let maxChangelogSummaryLen = 512

  /// All scalar fields stamped on an `ai_changelog` row by canonical write
  /// surfaces. `entityIds` holds the batch / bulk entity set persisted into the
  /// `ai_changelog_entities` join table; it is empty when the row covers only a
  /// single `entityId` (or zero entities).
  public struct ChangelogRow: Sendable {
    public var id: String
    public var timestamp: String
    public var operation: String
    public var entityType: String
    public var entityId: String?
    public var entityIds: [String]
    public var summary: String
    public var initiatedBy: String
    public var mcpTool: String?
    public var sourceDeviceId: String
    public var beforeJson: String?
    public var afterJson: String?
    /// Account-relative audit-retention generation carried on the sync upsert.
    public var retentionEpoch: Int64
    /// Local routing metadata; deliberately absent from the sync payload.
    public var retentionAccountIdentifier: String?

    public init(
      id: String,
      timestamp: String,
      operation: String,
      entityType: String,
      entityId: String? = nil,
      entityIds: [String] = [],
      summary: String,
      initiatedBy: String,
      mcpTool: String? = nil,
      sourceDeviceId: String,
      beforeJson: String? = nil,
      afterJson: String? = nil,
      retentionEpoch: Int64 = 0,
      retentionAccountIdentifier: String? = nil
    ) {
      self.id = id
      self.timestamp = timestamp
      self.operation = operation
      self.entityType = entityType
      self.entityId = entityId
      self.entityIds = entityIds
      self.summary = summary
      self.initiatedBy = initiatedBy
      self.mcpTool = mcpTool
      self.sourceDeviceId = sourceDeviceId
      self.beforeJson = beforeJson
      self.afterJson = afterJson
      self.retentionEpoch = retentionEpoch
      self.retentionAccountIdentifier = retentionAccountIdentifier
    }
  }

  /// Insert one row into `ai_changelog` and replace its entity-id registry.
  public static func writeChangelogRow(_ db: Database, _ row: ChangelogRow) throws {
    guard row.retentionEpoch >= 0 else {
      throw StoreError.validation("ai_changelog retention_epoch must be nonnegative")
    }
    try db.execute(
      sql: """
        INSERT INTO ai_changelog (
          id, timestamp, operation, entity_type, entity_id, summary,
          initiated_by, mcp_tool, source_device_id, before_json, after_json,
          retention_epoch, retention_account_identifier
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        row.id,
        row.timestamp,
        row.operation,
        row.entityType,
        row.entityId,
        row.summary,
        row.initiatedBy,
        row.mcpTool,
        row.sourceDeviceId,
        row.beforeJson,
        row.afterJson,
        row.retentionEpoch,
        row.retentionAccountIdentifier,
      ])
    try replaceChangelogEntities(db, changelogId: row.id, entityIds: row.entityIds)
  }

  /// Build the emit-once sync payload for one `ai_changelog` row.
  ///
  /// The append-only audit stream has no simple `(table, pk)`, so the generic
  /// outbox snapshot reader cannot read it; this is the dedicated builder for the
  /// bounded outbound path. It produces EXACTLY the keys the changelog apply
  /// handler reads on a peer, so an emitted envelope round-trips through id-dedup
  /// apply without a re-read:
  /// - `entity_ids` is a STRINGIFIED JSON array — a JSON *string* whose content
  ///   is the JSON array of the row's batch entity ids — matching how the applier
  ///   reads it as an optional string and re-parses via ``parseEntityIdsJson(_:)``.
  ///   An empty set emits JSON null (absent / null / empty all decode to "no
  ///   entities").
  /// - The nullable text columns emit JSON null when unset.
  public static func buildChangelogSyncPayload(_ row: ChangelogRow) throws -> JSONValue {
    guard row.retentionEpoch >= 0 else {
      throw StoreError.validation("ai_changelog retention_epoch must be nonnegative")
    }
    let entityIdsValue: JSONValue
    if row.entityIds.isEmpty {
      entityIdsValue = .null
    } else {
      entityIdsValue = .string(try canonicalizeJSON(.array(row.entityIds.map(JSONValue.string))))
    }
    return .object([
      "timestamp": .string(row.timestamp),
      "operation": .string(row.operation),
      "entity_type": .string(row.entityType),
      "entity_id": row.entityId.map(JSONValue.string) ?? .null,
      "entity_ids": entityIdsValue,
      "summary": .string(row.summary),
      "initiated_by": .string(row.initiatedBy),
      "mcp_tool": row.mcpTool.map(JSONValue.string) ?? .null,
      "source_device_id": .string(row.sourceDeviceId),
      "before_json": row.beforeJson.map(JSONValue.string) ?? .null,
      "after_json": row.afterJson.map(JSONValue.string) ?? .null,
      "retention_epoch": .int(row.retentionEpoch),
    ])
  }

  /// Replace the changelog row's full entity-id registry with the provided
  /// list. An empty list clears the registry. `INSERT OR IGNORE` silently
  /// tolerates duplicate `(changelog_id, entity_id)` pairs in the input.
  public static func replaceChangelogEntities(
    _ db: Database, changelogId: String, entityIds: [String]
  ) throws {
    try db.execute(
      sql: "DELETE FROM ai_changelog_entities WHERE changelog_id = ?1",
      arguments: [changelogId])
    guard !entityIds.isEmpty else { return }
    let stmt = try db.makeStatement(
      sql: "INSERT OR IGNORE INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?1, ?2)")
    for id in entityIds {
      try stmt.execute(arguments: [changelogId, id])
    }
  }

  /// Parse a wire-form JSON array of strings. `nil`, `""`, and whitespace-only
  /// input all return the empty array. Invalid JSON surfaces as
  /// ``StoreError/validation(_:)``.
  public static func parseEntityIdsJson(_ raw: String?) throws -> [String] {
    guard let raw else { return [] }
    if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
    guard case .array(let elements)? = JSONValue.parse(raw) else {
      throw StoreError.validation("invalid ai_changelog entity_ids JSON: \(raw)")
    }
    var out: [String] = []
    out.reserveCapacity(elements.count)
    for element in elements {
      guard case .string(let s) = element else {
        throw StoreError.validation("invalid ai_changelog entity_ids JSON: \(raw)")
      }
      out.append(s)
    }
    return out
  }

  /// Sanitize a human-readable summary at the audit-write boundary: collapse
  /// every control character to a single space, collapse runs of whitespace,
  /// and cap total length at ``maxChangelogSummaryLen`` characters with a
  /// trailing `…` marker. A summary at exactly the cap is not truncated.
  public static func sanitizeChangelogSummary(_ raw: String) -> String {
    var out = String.UnicodeScalarView()
    var lastWasSpace = false
    var charCount = 0
    var truncated = false
    var iter = raw.unicodeScalars.makeIterator()
    var pending = iter.next()
    while let ch = pending {
      pending = iter.next()
      let replacement: Unicode.Scalar = isControlScalar(ch) ? " " : ch
      if replacement == " " && lastWasSpace { continue }
      lastWasSpace = replacement == " "
      out.append(replacement)
      charCount += 1
      if charCount >= maxChangelogSummaryLen {
        truncated = pending != nil
        break
      }
    }
    let trimmed = String(String.UnicodeScalarView(out)).reversedTrimmedTrailingSpaces()
    if truncated {
      var capped = String(trimmed.prefix(maxChangelogSummaryLen - 1))
      capped.append("…")
      return capped
    }
    return trimmed
  }

  /// Serialize a state snapshot to a size-capped JSON string. Returns `nil`
  /// when the input is `nil`. An over-budget payload is replaced by a valid
  /// JSON sentinel whose `preview` ends in `…`; downstream readers can therefore
  /// distinguish truncation without violating the manifest's `json-string`
  /// invariant or failing an entire outbound transaction.
  public static func encodeStateJson(_ value: JSONValue?) throws -> String? {
    guard let value else { return nil }
    let raw = try canonicalizeJSON(value)
    let originalByteCount = raw.utf8.count
    if originalByteCount <= maxChangelogStateJsonBytes { return raw }

    // Binary-search a Unicode-scalar prefix because JSON string escaping can
    // expand quotes, backslashes, and controls. Measuring the final canonical
    // sentinel on every probe is the only reliable byte-budget calculation.
    let scalars = Array(raw.unicodeScalars)
    var lowerBound = 0
    var upperBound = scalars.count
    var best: String?
    while lowerBound <= upperBound {
      let count = lowerBound + (upperBound - lowerBound) / 2
      let prefix = String(String.UnicodeScalarView(scalars.prefix(count))) + "…"
      let candidate = try canonicalizeJSON(
        .object([
          "_lorvex_truncated": .bool(true),
          "original_bytes": .int(Int64(originalByteCount)),
          "preview": .string(prefix),
        ]))
      if candidate.utf8.count <= maxChangelogStateJsonBytes {
        best = candidate
        lowerBound = count + 1
      } else {
        if count == 0 { break }
        upperBound = count - 1
      }
    }
    guard let best else {
      throw StoreError.invariant("changelog truncation sentinel exceeds byte budget")
    }
    return best
  }

  private static func isControlScalar(_ s: Unicode.Scalar) -> Bool {
    // Unicode general category Cc control characters (C0 + C1).
    s.value < 0x20 || (s.value >= 0x7F && s.value <= 0x9F)
  }

}

extension String {
  /// Drop trailing scalars whose Unicode `White_Space` property is set.
  fileprivate func reversedTrimmedTrailingSpaces() -> String {
    var scalars = Array(unicodeScalars)
    while let last = scalars.last, last.properties.isWhitespace {
      scalars.removeLast()
    }
    return String(String.UnicodeScalarView(scalars))
  }
}
