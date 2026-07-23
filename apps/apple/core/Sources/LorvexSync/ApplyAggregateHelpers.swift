import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Shared apply-time primitives for the per-entity aggregate appliers (`task`,
/// `list`, and the deferred `habit` / `calendar_event`).
///
/// Three independent concerns live here:
///
///   * The parse-then-compare LWW delete gate
///     (``ApplyAggregate/evaluateDeleteLww(_:readVersionSQL:entityId:incomingVersion:tieBreak:)``)
///     plus the gate-before-cascade sequencer
///     (``ApplyAggregate/gateThenCascade(_:readVersionSQL:deleteSQL:entityId:incomingVersion:tieBreak:cascade:)``).
///   * The partial-patch JSON tri-state extraction (`absent` / `clear` / `set`)
///     with the `(value, present)` split the partial-update UPDATE template
///     binds.
///   * The cascading-tombstone fanout helpers
///     (``ApplyAggregate/tombstoneCompositeEdges`` / ``ApplyAggregate/tombstoneChildRows``)
///     that pre-tombstone child / edge rows ahead of SQLite's `ON DELETE
///     CASCADE`, each stamped at `max(parentVersion, rowVersion)`.
enum ApplyAggregate {

  // MARK: - LWW delete gate

  /// Outcome of the parse-then-compare LWW delete gate.
  ///
  /// HLC strings are fixed-width and lex-ordered so a byte compare yields the
  /// right answer for two well-formed HLCs, but a stale-shape literal (`"v1"`,
  /// `"seed"`) slips past in either direction (ASCII letters sort above digits).
  /// We reject the delete when both sides parse AND the local one strictly
  /// dominates; on parse failure either side we fall back to a byte compare so a
  /// tainted local version that sorts strictly greater than the envelope's still
  /// refuses the delete.
  enum DeleteLwwDecision: Equatable {
    /// Incoming version dominates (or row missing / NULL version / unparseable
    /// AND the byte-compare fallback admits); the caller may run the unguarded
    /// DELETE body.
    case apply
    /// Local row's version strictly dominates the incoming version; the caller
    /// MUST NOT delete. Carries both versions so the caller can record the
    /// conflict-log row attributing the loss.
    case reject(localVersion: String, envelopeVersion: String)
  }

  /// Parse-then-compare LWW gate for the aggregate `apply*Delete` paths.
  ///
  /// `readVersionSQL` must be of the shape `SELECT version FROM <table> WHERE
  /// <pk> = ?`. Returns ``DeleteLwwDecision/apply`` when the row is absent / has
  /// NULL version / the incoming version dominates (parsed or via the
  /// byte-compare fallback). Returns ``DeleteLwwDecision/reject(localVersion:envelopeVersion:)``
  /// when both versions parse and the local one strictly dominates, OR
  /// (parse-failure fallback) when the local string strictly sorts above the
  /// envelope's.
  ///
  /// `tieBreak.allowsEqual` follows the upsert convention — production
  /// `apply*Delete` callers route here with `.allowEqual` (matching the
  /// `:version >= version` SQL predicate) so shadow-promotion replay stays
  /// idempotent.
  static func evaluateDeleteLww(
    _ db: Database, readVersionSQL: String, entityId: String, incomingVersion: String,
    tieBreak: LwwTieBreak
  ) throws -> DeleteLwwDecision {
    try evaluateLwwDeleteWithSelect(
      db, selectSQL: readVersionSQL, entityId: entityId, incomingVersion: incomingVersion,
      tieBreak: tieBreak, errorLogKind: "sync.apply.delete_lww_unparseable_version")
  }

  /// Shared LWW delete-decision gate. The `selectSQL` template controls the
  /// WHERE shape (e.g. `id = ?` for aggregate rows) so each caller keeps its
  /// bind shape but inherits the same parse-then-compare
  /// decision semantics and the same error-log key family for the byte-compare
  /// fallback path.
  static func evaluateLwwDeleteWithSelect(
    _ db: Database, selectSQL: String, entityId: String, incomingVersion: String,
    tieBreak: LwwTieBreak, errorLogKind: String
  ) throws -> DeleteLwwDecision {
    let local: String?
    do {
      local = try String.fetchOne(db, sql: selectSQL, arguments: [entityId])
    } catch { throw ApplyError.lift(error) }
    // Row absent or NULL local version — admit the (no-op / freshly-inserted)
    // delete.
    guard let localVersion = local else { return .apply }

    let incomingParses = (try? Hlc.parseCanonical(incomingVersion)) != nil
    let localParses = (try? Hlc.parseCanonical(localVersion)) != nil
    let cmp = compareVersionsWithFallback(incomingVersion, localVersion)
    if !incomingParses || !localParses {
      // A tainted local version (or a malformed envelope) lost typed-LWW
      // arbitration and fell back to a byte compare. Log the corruption so
      // diagnostics surface the unparseable version; the byte-compare result
      // still refuses a delete when the local string sorts strictly greater
      // than the envelope's.
      let message =
        "delete LWW gate falling back to byte-compare for "
        + "entity_id=\(entityId), incoming=\(applyDebugQuoted(incomingVersion)), "
        + "local=\(applyDebugQuoted(localVersion))"
      // Route through the shared redact-then-truncate writer (uniform contract).
      ErrorLog.appendBestEffort(
        db, source: errorLogKind, message: message, details: nil, level: "error")
    }
    let dominates: Bool
    switch cmp {
    case .orderedDescending: dominates = true
    case .orderedSame: dominates = tieBreak.allowsEqual
    case .orderedAscending: dominates = false
    }
    if dominates {
      return .apply
    }
    return .reject(localVersion: localVersion, envelopeVersion: incomingVersion)
  }

  /// Outcome of ``gateThenCascade``. The gate runs BEFORE the cascade — running
  /// it afterward would let a stale-but-byte-compare-rejecting envelope mint
  /// cascade tombstones over child / edge rows whose live parent then stays
  /// alive, after which peers' subsequent edge upserts could never lift those
  /// tombstones and the cluster would diverge permanently on edge state.
  enum CascadingDeleteDecision: Equatable {
    case applied
    case rejected(localVersion: String)
  }

  /// Uniform "gate before cascade" sequencer for every aggregate `apply*Delete`
  /// whose delete fans out child / edge tombstones:
  ///
  /// 1. ``evaluateDeleteLww`` against the parent row's version. On `reject`
  ///    (parsed HLC compare OR byte-compare fallback), short-circuits with
  ///    `rejected` and the cascade closure NEVER runs.
  /// 2. On `apply`, runs `cascade` (which fans out child / edge tombstones).
  /// 3. On cascade success, runs the parent DELETE under `deleteSQL` (must be of
  ///    the shape `DELETE FROM <table> WHERE <pk> = :id`).
  static func gateThenCascade(
    _ db: Database, readVersionSQL: String, deleteSQL: String, entityId: String,
    incomingVersion: String, tieBreak: LwwTieBreak, cascade: (Database) throws -> Void
  ) throws -> CascadingDeleteDecision {
    switch try evaluateDeleteLww(
      db, readVersionSQL: readVersionSQL, entityId: entityId, incomingVersion: incomingVersion,
      tieBreak: tieBreak)
    {
    case let .reject(localVersion, _):
      return .rejected(localVersion: localVersion)
    case .apply:
      try cascade(db)
      do {
        try db.execute(sql: deleteSQL, arguments: ["id": entityId])
      } catch { throw ApplyError.lift(error) }
      return .applied
    }
  }

  // MARK: - Partial-patch JSON tri-state

  /// Tri-state optional string for nullable columns where "explicit clear" must
  /// be distinguishable from "field absent".
  ///
  /// * ``Patch/unset`` — key absent from the JSON object (no change intent).
  /// * ``Patch/clear`` — key present as JSON `null` OR an empty string `""`.
  ///   Older peers serialize "clear" as `""`, newer peers as `null`; both
  ///   collapse to the same SQL NULL so the clear fans out.
  /// * ``Patch/set(_:)`` — key present with a non-empty string value.
  static func optionalStrPreservingEmpty(
    _ obj: [String: JSONValue], _ key: String, _ entity: String
  ) throws -> Patch<String> {
    switch obj[key] {
    case .none:
      return .unset
    case .null:
      return .clear
    case let .string(s):
      return s.isEmpty ? .clear : .set(s)
    default:
      throw ApplyError.invalidPayload(
        "\(entity) payload: \(key) must be a string when present")
    }
  }

  /// Tri-state optional integer mirroring ``optionalStrPreservingEmpty``:
  /// * ``Patch/unset`` — key absent.
  /// * ``Patch/clear`` — key present with JSON `null`.
  /// * ``Patch/set(_:)`` — key present with an integer value.
  static func optionalInt64PreservingNull(
    _ obj: [String: JSONValue], _ key: String, _ entity: String
  ) throws -> Patch<Int64> {
    switch obj[key] {
    case .none:
      return .unset
    case .null:
      return .clear
    case let .int(i):
      return .set(i)
    default:
      throw ApplyError.invalidPayload(
        "\(entity) payload: \(key) must be an integer when present")
    }
  }

  /// Flatten a tri-state string patch to a simple `String?` for binding into a
  /// nullable SQL column. Both `unset` and `clear` collapse to SQL NULL;
  /// `set(s)` passes through.
  static func nullableStrOrClear(_ val: Patch<String>) -> String? { val.asBindValue }

  /// Split a tri-state string patch into the `(value, present)` pair the
  /// `INSERT … ON CONFLICT` upsert needs to distinguish "field absent from
  /// envelope" (preserve the existing column) from "field present, possibly with
  /// an explicit clear" (write the new value, including SQL NULL).
  static func splitPartialStrValue(_ val: Patch<String>) -> (String?, Int64) {
    switch val {
    case .unset: return (nil, 0)
    case .clear: return (nil, 1)
    case let .set(s): return (s, 1)
    }
  }

  /// Integer-column variant of ``splitPartialStrValue``.
  static func splitPartialInt64Value(_ val: Patch<Int64>) -> (Int64?, Int64) {
    switch val {
    case .unset: return (nil, 0)
    case .clear: return (nil, 1)
    case let .set(n): return (n, 1)
    }
  }

  /// Apply the Unicode hygiene scrubber so inbound sync payloads cannot smuggle
  /// bidi overrides, zero-width chars, or line separators into local text
  /// columns.
  static func scrub(_ s: String) -> String { UnicodeHygiene.sanitizeUserText(s) }

  static func scrubOpt(_ s: String?) -> String? { s.map(scrub) }

  // MARK: - Cascading tombstones

  /// Pick the larger of two HLC strings (parent's cascade version vs. the child
  /// row's own version). On parse failure the parent version wins — the caller
  /// already validated `parentVersion` upstream, and any local row whose version
  /// column is malformed is itself corrupt; we'd rather still emit the cascade
  /// tombstone than fail the apply batch.
  private static func maxCascadeVersion(_ parentVersion: String, _ rowVersion: String) -> String {
    guard let parentHlc = try? Hlc.parseCanonical(parentVersion) else { return parentVersion }
    guard let rowHlc = try? Hlc.parseCanonical(rowVersion) else { return parentVersion }
    return rowHlc > parentHlc ? rowVersion : parentVersion
  }

  /// Tombstone composite-edge child rows (`{parentId}:{otherId}` shape: task_tag,
  /// task_dependency, task_calendar_event_link, habit_completion). The
  /// `composeId` closure lets the caller flip the order (task delete fans out
  /// task_dependency in both directions). Each tombstone is stamped at
  /// `max(version, rowVersion)`.
  ///
  /// `selectSQL` must SELECT `(otherIdColumn, version)` keyed on the parent id.
  static func tombstoneCompositeEdges(
    _ db: Database, selectSQL: String, parentId: String, entityType: String,
    composeId: (String) -> String, version: String, deletedAt: String
  ) throws {
    let rows: [(String, String)]
    do {
      rows = try Row.fetchAll(db, sql: selectSQL, arguments: [parentId]).map {
        ($0[0], $0[1])
      }
    } catch { throw ApplyError.lift(error) }
    for (other, rowVersion) in rows {
      let edgeId = composeId(other)
      let cascadeVersion = maxCascadeVersion(version, rowVersion)
      try Tombstone.createTombstone(
        db, entityType: entityType, entityId: edgeId, version: cascadeVersion,
        deletedAt: deletedAt)
    }
  }

  /// Tombstone child rows with their own single-column PKs (task_reminder,
  /// task_checklist_item, habit_reminder_policy). `selectSQL` must SELECT
  /// `(id, version)` keyed on the parent id.
  static func tombstoneChildRows(
    _ db: Database, selectSQL: String, parentId: String, entityType: String,
    version: String, deletedAt: String
  ) throws {
    let rows: [(String, String)]
    do {
      rows = try Row.fetchAll(db, sql: selectSQL, arguments: [parentId]).map {
        ($0[0], $0[1])
      }
    } catch { throw ApplyError.lift(error) }
    for (id, rowVersion) in rows {
      let cascadeVersion = maxCascadeVersion(version, rowVersion)
      try Tombstone.createTombstone(
        db, entityType: entityType, entityId: id, version: cascadeVersion,
        deletedAt: deletedAt)
    }
  }
}
