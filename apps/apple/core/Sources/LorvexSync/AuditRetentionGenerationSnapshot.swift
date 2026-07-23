import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Read-only retained-audit contribution to a unified candidate-generation
/// snapshot. The unified snapshot layer merges these envelopes with ordinary
/// live/tombstone records, binds the read to `local_change_seq`, and paginates
/// the combined stable order; this component never consumes the domain outbox.
public struct AuditRetentionGenerationSnapshotComponent: Sendable, Equatable {
  public var envelopes: [SyncEnvelope]
  public var recordCount: Int
  public var witnessDigest: String

  public init(
    envelopes: [SyncEnvelope], recordCount: Int, witnessDigest: String
  ) {
    self.envelopes = envelopes
    self.recordCount = recordCount
    self.witnessDigest = witnessDigest
  }
}

extension AuditRetentionFrontier {
  /// Maximum retained audit records copied into one candidate generation.
  /// Local retention already applies the same hard bound; exceeding it here is
  /// a fail-closed signal that maintenance did not complete, never permission
  /// to publish a partial generation.
  public static let maximumGenerationSnapshotRecords = 10_000

  /// Produce the complete retained-audit part of an authorized candidate-zone
  /// snapshot without writing any table, especially `sync_outbox`.
  ///
  /// The result is bounded and stable-sorted by `(timestamp, entity_id)`. Audit
  /// convergence is identity-dedup rather than LWW, so rows whose original
  /// outbox entry has already been GC'd use a deterministic, low synthetic HLC
  /// derived from the immutable audit id. Canonical audit content is untouched,
  /// retries produce byte-identical envelopes, and unchanged data never inflates
  /// a business clock.
  public static func generationSnapshotComponent(
    _ db: Database, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionGenerationSnapshotComponent {
    let accountState = try validateOutboundAuthorization(
      db, authorization: authorization)
    return try generationSnapshotComponent(
      db, accountIdentifier: authorization.accountIdentifier,
      accountState: accountState)
  }

  /// Candidate-zone twin that validates the staged capability while leaving
  /// the canonical active-zone binding untouched.
  public static func generationSnapshotComponent(
    _ db: Database, candidateAuthorization: AuditRetentionCandidateAuthorization
  ) throws -> AuditRetentionGenerationSnapshotComponent {
    let accountState = try validateCandidateAuthorization(
      db, authorization: candidateAuthorization)
    return try generationSnapshotComponent(
      db, accountIdentifier: candidateAuthorization.accountIdentifier,
      accountState: accountState)
  }

  static func generationSnapshotPreflightCount(
    _ db: Database, authorization: AuditRetentionOutboundAuthorization
  ) throws -> (count: Int, state: AuditRetentionAccountState) {
    let state = try validateOutboundAuthorization(db, authorization: authorization)
    return (
      try generationSnapshotPreflightCount(
        db, accountIdentifier: authorization.accountIdentifier, accountState: state),
      state)
  }

  static func generationSnapshotPreflightCount(
    _ db: Database, candidateAuthorization: AuditRetentionCandidateAuthorization
  ) throws -> (count: Int, state: AuditRetentionAccountState) {
    let state = try validateCandidateAuthorization(
      db, authorization: candidateAuthorization)
    return (
      try generationSnapshotPreflightCount(
        db, accountIdentifier: candidateAuthorization.accountIdentifier,
        accountState: state),
      state)
  }

  static func forEachGenerationSnapshotEnvelope(
    _ db: Database, authorization: AuditRetentionOutboundAuthorization,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let state = try validateOutboundAuthorization(db, authorization: authorization)
    try forEachGenerationSnapshotEnvelope(
      db, accountIdentifier: authorization.accountIdentifier,
      accountState: state, consume)
  }

  static func forEachGenerationSnapshotEnvelope(
    _ db: Database, candidateAuthorization: AuditRetentionCandidateAuthorization,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let state = try validateCandidateAuthorization(
      db, authorization: candidateAuthorization)
    try forEachGenerationSnapshotEnvelope(
      db, accountIdentifier: candidateAuthorization.accountIdentifier,
      accountState: state, consume)
  }

  private static func generationSnapshotComponent(
    _ db: Database, accountIdentifier: String,
    accountState: AuditRetentionAccountState
  ) throws -> AuditRetentionGenerationSnapshotComponent {
    var envelopes: [SyncEnvelope] = []
    try forEachGenerationSnapshotEnvelope(
      db, accountIdentifier: accountIdentifier, accountState: accountState
    ) { envelopes.append($0) }
    return AuditRetentionGenerationSnapshotComponent(
      envelopes: envelopes, recordCount: envelopes.count,
      witnessDigest: try GenerationSnapshot.auditCanonicalDigest(envelopes))
  }

  private static func generationSnapshotPreflightCount(
    _ db: Database, accountIdentifier: String,
    accountState: AuditRetentionAccountState
  ) throws -> Int {
    let count = try Int.fetchOne(
      db,
      sql: "SELECT COUNT(*) FROM ai_changelog WHERE retention_account_identifier = ?",
      arguments: [accountIdentifier]) ?? 0
    guard count <= maximumGenerationSnapshotRecords else {
      throw AuditRetentionStateError.generationSnapshotLimitExceeded(
        limit: maximumGenerationSnapshotRecords, observedAtLeast: count)
    }
    if accountState.policy == .off, count != 0 {
      let first = try String.fetchOne(
        db,
        sql: """
          SELECT id FROM ai_changelog WHERE retention_account_identifier = ?
          ORDER BY timestamp ASC, id ASC LIMIT 1
          """,
        arguments: [accountIdentifier]) ?? "invalid"
      throw AuditRetentionStateError.invalidGenerationSnapshotRow(first)
    }
    return count
  }

  private static func forEachGenerationSnapshotEnvelope(
    _ db: Database, accountIdentifier: String,
    accountState: AuditRetentionAccountState,
    _ consume: (SyncEnvelope) throws -> Void
  ) throws {
    let expectedCount = try generationSnapshotPreflightCount(
      db, accountIdentifier: accountIdentifier, accountState: accountState)
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, timestamp, retention_epoch, source_device_id
        FROM ai_changelog
        WHERE retention_account_identifier = ?
        ORDER BY timestamp ASC, id ASC
        LIMIT ?
        """,
      arguments: [
        accountIdentifier, maximumGenerationSnapshotRecords + 1,
      ])
    guard rows.count == expectedCount else {
      throw AuditRetentionStateError.invalidGenerationSnapshotRow("inventory-drift")
    }

    for row in rows {
      let entityId: String = row["id"]
      let timestamp: String = row["timestamp"]
      let epoch: Int64 = row["retention_epoch"]
      guard epoch == accountState.frontierEpoch,
        !rowIsDominated(
          epoch: epoch, timestamp: timestamp, entityId: entityId,
          by: accountState.frontier),
        let canonicalObject = try canonicalAuditPayloadObject(db, entityId: entityId)
      else {
        throw AuditRetentionStateError.invalidGenerationSnapshotRow(entityId)
      }

      let version = try deterministicGenerationSnapshotVersion(entityId: entityId)
      var versionedObject = canonicalObject
      versionedObject["version"] = .string(version.description)
      let payload = try SyncCanonicalize.canonicalizeJSON(.object(versionedObject))
      let deviceId = try generationSnapshotDeviceId(
        sourceDeviceId: row["source_device_id"], entityId: entityId)
      let envelope = SyncEnvelope(
        entityType: .aiChangelog, entityId: entityId, operation: .upsert,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: deviceId)
      guard case .success = envelope.validate() else {
        throw AuditRetentionStateError.invalidGenerationSnapshotRow(entityId)
      }
      try consume(envelope)
    }
  }

  /// Validate the opaque authorization against the exact active account, zone,
  /// frontier, and durable token. Snapshot enumeration and mark-before-cloud
  /// calls share this gate.
  static func validateOutboundAuthorization(
    _ db: Database, authorization: AuditRetentionOutboundAuthorization
  ) throws -> AuditRetentionAccountState {
    let accountIdentifier = authorization.accountIdentifier
    let zoneName = authorization.zoneName
    try requireActiveContext(
      db, requestedAccount: accountIdentifier, requestedZone: zoneName)
    guard let accountState = try state(db, accountIdentifier: accountIdentifier) else {
      throw AuditRetentionStateError.malformedAccountState(accountIdentifier)
    }
    guard accountState.isPolicyReady else {
      throw AuditRetentionStateError.policyNotReady(accountIdentifier)
    }
    guard accountState.frontier == authorization.frontier,
      let authorizationRow = try Row.fetchOne(
        db,
        sql: """
          SELECT token, account_identifier, zone_name, frontier_epoch,
                 frontier_cutoff_timestamp, frontier_cutoff_entity_id
          FROM audit_retention_outbound_authorization WHERE singleton = 1
          """),
      authorizationRow["token"] as String == authorization.token,
      authorizationRow["account_identifier"] as String == accountIdentifier,
      authorizationRow["zone_name"] as String == zoneName,
      authorizationRow["frontier_epoch"] as Int64 == authorization.frontier.epoch,
      authorizationRow["frontier_cutoff_timestamp"] as String
        == authorization.frontier.minimumRetainedTimestamp,
      authorizationRow["frontier_cutoff_entity_id"] as String
        == authorization.frontier.minimumRetainedEntityId
    else { throw AuditRetentionStateError.invalidOutboundAuthorization }
    return accountState
  }

  /// Canonical wire-owned audit projection, excluding synthetic envelope
  /// `version`. Shared by generation snapshot and mark-before-cloud validation.
  static func canonicalAuditPayloadObject(
    _ db: Database, entityId: String
  ) throws -> [String: JSONValue]? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT timestamp, operation, entity_type, entity_id, summary,
                 initiated_by, mcp_tool, source_device_id, before_json,
                 after_json, retention_epoch
          FROM ai_changelog WHERE id = ?
          """,
        arguments: [entityId])
    else { return nil }
    let entityIds = try String.fetchAll(
      db,
      sql: """
        SELECT entity_id FROM ai_changelog_entities
        WHERE changelog_id = ? ORDER BY entity_id ASC
        """,
      arguments: [entityId])
    let entityIdsValue: JSONValue =
      entityIds.isEmpty
      ? .null
      : .string(
        try SyncCanonicalize.canonicalizeJSON(
          .array(entityIds.map(JSONValue.string))))
    let nullable: (String?) -> JSONValue = { $0.map(JSONValue.string) ?? .null }
    return [
      "timestamp": .string(row["timestamp"] as String),
      "operation": .string(row["operation"] as String),
      "entity_type": .string(row["entity_type"] as String),
      "entity_id": nullable(row["entity_id"] as String?),
      "entity_ids": entityIdsValue,
      "summary": .string(row["summary"] as String),
      "initiated_by": .string(row["initiated_by"] as String),
      "mcp_tool": nullable(row["mcp_tool"] as String?),
      "source_device_id": nullable(row["source_device_id"] as String?),
      "before_json": nullable(row["before_json"] as String?),
      "after_json": nullable(row["after_json"] as String?),
      "retention_epoch": .int(row["retention_epoch"] as Int64),
    ]
  }

  static func deterministicGenerationSnapshotVersion(
    entityId: String
  ) throws -> Hlc {
    let digest = Sha256Checksum.hexDigest(
      Data("audit-generation-snapshot\u{0}\(entityId)".utf8))
    return try Hlc(
      physicalMs: 0, counter: 0,
      deviceSuffix: String(digest.prefix(HlcConstants.deviceSuffixHexLen)))
  }

  static func generationSnapshotDeviceId(
    sourceDeviceId: String?, entityId: String
  ) throws -> String {
    if let sourceDeviceId, !sourceDeviceId.isEmpty,
      sourceDeviceId.utf8.count <= SyncEnvelope.maxEnvelopeDeviceIdLen
    {
      return sourceDeviceId
    }
    let digest = Sha256Checksum.hexDigest(Data(entityId.utf8))
    return "audit-snapshot-\(digest.prefix(32))"
  }

}
