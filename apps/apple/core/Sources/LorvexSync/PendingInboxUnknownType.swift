import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Forward-compat "future record" lane for the pending inbox (S-4).
///
/// A CloudKit record that is well-formed but not yet interpretable — a FUTURE
/// `entity_type` (the kind is a closed enum) or, on a forward-compat record, a
/// future `operation` — cannot become a ``SyncEnvelope``, so the transport parks
/// its raw fields here instead of dropping it while the change token advances past
/// it. The parked row is the ONLY local copy of the record. It is HELD, never
/// quarantined and never horizon-reaped: its `attempt_count` is fixed at its
/// initial value so the per-row retry cap can never shed it, and the retention
/// sweep exempts it from the horizon GC (superseded parked versions of the same
/// entity coalesce instead, via
/// ``SyncRetention/coalesceSupersededHoldsPastHorizon(_:horizonDays:)``). On a
/// later build whose ``LorvexDomain/EntityKind`` / operation set understands it,
/// the parked envelope JSON deserializes normally and the drain's apply path runs.
///
/// Uses the HOLD semantics of the `schema_too_new` deferral (timestamp-only
/// refresh, no attempt bump); the distinction is that schema-too-new is keyed
/// off a typed ``SyncEnvelope`` while this lane stores ``RawEnvelopeFields``.
extension PendingInboxDrain {
  /// `reason` value stamped on a parked future record. The drain keys its
  /// HOLD-vs-poison decision off this marker. Named for the original
  /// unknown-entity_type case; kept stable so rows parked by an earlier build
  /// still match after an upgrade.
  static let entityTypeTooNewReason = "entity_type_too_new"

  /// Durably park a future record (unknown type / future operation) under HOLD
  /// semantics.
  ///
  /// UPSERTs on the `(entity_type, entity_id, version)` identity so repeated
  /// deliveries of the same record coalesce onto one row. Unlike the FK-deferral
  /// enqueue, a duplicate delivery refreshes `last_attempted_at` (and the stored
  /// body) but never touches `attempt_count` — the retry cap must not apply to a
  /// record that is correct and merely not-yet-understood.
  public static func holdUnknownTypeRecord(_ db: Database, raw: RawEnvelopeFields) throws {
    guard case .success = raw.validate() else {
      throw EnqueueError.malformedPayload(
        "future record failed the bounded raw-envelope contract")
    }
    try StoreTransactions.withSavepoint(db, "hold_unknown_future_record") { db in
      let envelopeJSON = try raw.envelopeWireJSON()
      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox
              (envelope, reason, missing_entity_type, missing_entity_id,
               envelope_entity_type, envelope_entity_id, envelope_version,
               first_attempted_at, last_attempted_at, attempt_count)
           VALUES (?, ?, NULL, NULL, ?, ?, ?,
                   strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                   strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                   1)
           ON CONFLICT(envelope_entity_type, envelope_entity_id, envelope_version)
           DO UPDATE SET
               envelope          = excluded.envelope,
               reason            = excluded.reason,
               last_attempted_at = excluded.last_attempted_at
          """,
        arguments: [
          envelopeJSON, entityTypeTooNewReason, raw.entityType, raw.entityId, raw.version,
        ])
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: raw.entityType, entityId: raw.entityId, heldVersion: raw.version)
    }
  }

  /// Count exact future-authored records that this build still cannot apply.
  ///
  /// These rows are the only durable copy after a CloudKit cursor advances. A
  /// generation rebuild must therefore retain its predecessor while this count
  /// is nonzero: the immutable candidate snapshot can encode canonical rows and
  /// payload shadows, but cannot encode a future entity kind or operation. The
  /// predicate intentionally excludes standing aggregate/audit deferrals; those
  /// are current-schema records whose canonical state remains representable.
  public static func unresolvedFutureRecordCount(_ db: Database) throws -> Int {
    try Int.fetchOne(
      db,
      sql: """
        SELECT COUNT(*)
        FROM sync_pending_inbox
        WHERE reason = ?
           OR reason LIKE ?
           OR reason LIKE ?
        """,
      arguments: [
        entityTypeTooNewReason,
        "\(DeferralReason.schemaTooNewReasonMarker)%",
        "\(DeferralReason.operationallyUnusableHlcReasonMarker)%",
      ]) ?? 0
  }

  /// Whether a pending row originated as future-authored data whose cursor has
  /// already advanced. Keep this provenance while an upgraded build can parse
  /// the envelope but still waits on a dependency; otherwise changing its
  /// reason to `missing_dependency` would let generation publication and horizon
  /// GC forget that the row remains the only durable remote copy.
  static func isFutureRecordHoldReason(_ reason: String) -> Bool {
    reason == entityTypeTooNewReason
      || reason.hasPrefix(DeferralReason.schemaTooNewReasonMarker)
      || reason.hasPrefix(DeferralReason.operationallyUnusableHlcReasonMarker)
  }

  /// SQL twin of ``isFutureRecordHoldReason(_:)`` for identity-scoped safety
  /// queries. Deliberately excludes ordinary FK, audit-frontier, and aggregate
  /// invariant holds: none means a newer app owns the CloudKit record shape.
  static func futureRecordReasonSQL(column: String) -> String {
    """
    \(column) = '\(entityTypeTooNewReason)'
    OR \(column) LIKE '\(DeferralReason.schemaTooNewReasonMarker)%'
    OR \(column) LIKE '\(DeferralReason.operationallyUnusableHlcReasonMarker)%'
    """
  }

  /// Whether a pending row is a HELD future record the drain must NOT treat as
  /// poison. Consulted only in the drain's parse-FAILURE branch (the stored body
  /// did not deserialize into a ``SyncEnvelope``). True when the row was parked by
  /// the future-record lane AND it is still not interpretable by this build:
  ///
  /// * its stored `entity_type` is still unknown (a new kind need not bump the
  ///   schema), OR
  /// * the record is still forward-compat (`payload_schema_version` ahead of this
  ///   build) — its future operation is not understood yet.
  ///
  /// Once the build catches up, the envelope deserializes and the drain never
  /// reaches this branch; a body that still fails to parse at a known type AND a
  /// caught-up schema is genuine corruption → returns false and falls through to
  /// quarantine.
  static func isHeldFutureRecord(_ entry: PendingInbox.Entry) -> Bool {
    guard entry.reason == entityTypeTooNewReason,
      let probe = decodeFutureProbe(entry.envelopeJSON)
    else { return false }
    if EntityKind.parse(probe.entityType) == nil { return true }
    return probe.payloadSchemaVersion > LorvexVersion.payloadSchemaVersion
  }

  /// Extract the `entity_type` + `payload_schema_version` from a stored envelope
  /// JSON body, or `nil` if the body is unreadable or lacks a field.
  private static func decodeFutureProbe(_ json: String) -> FutureRecordProbe? {
    guard let data = json.data(using: .utf8),
      let probe = try? JSONDecoder().decode(FutureRecordProbe.self, from: data)
    else { return nil }
    return probe
  }

  private struct FutureRecordProbe: Decodable {
    let entityType: String
    let payloadSchemaVersion: UInt32
    enum CodingKeys: String, CodingKey {
      case entityType = "entity_type"
      case payloadSchemaVersion = "payload_schema_version"
    }
  }
}
