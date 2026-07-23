import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// A `(entityType, entityId)` an apply pass produced a diverged merged row for and
/// therefore needs a fresh-HLC merged-snapshot re-emit. The drain collects these
/// into its ``PendingInboxDrain/DrainSummary`` so the driver — which holds the HLC
/// clock + device identity — can mint and enqueue the re-emit.
public struct AbsenceReemitTarget: Sendable, Equatable {
  public let entityType: String
  public let entityId: String
  public let listFallbackPayloadListId: String?
  public init(
    entityType: String, entityId: String, listFallbackPayloadListId: String? = nil
  ) {
    self.entityType = entityType
    self.entityId = entityId
    self.listFallbackPayloadListId = listFallbackPayloadListId
  }
}

/// Re-emit detection for rows that diverge from the envelope that landed them,
/// so a peer that only saw that envelope converges. Sources include rolling-
/// schema field preservation, SYNC-MED-2, and the `resolveListId` fallback:
///
///   * Rolling payload schemas — either this runtime knows fields introduced
///     after the inbound schema, or an older runtime retained a higher-schema
///     payload shadow while applying a legacy update.
///
///   * Absence-preserving child collections — the aggregate appliers preserve an
///     entity's child collection (current_focus items, daily_review task/list
///     links) when the inbound envelope OMITS that key rather than wiping it.
///     Preservation makes the merged local row differ from the envelope.
///   * Per-device `list_id` fallback — a `task` upsert whose payload named a
///     `list_id` this device has tombstoned lands in the device's inbox/oldest
///     fallback instead, so the merged row's list differs from the envelope.
///   * Calendar base grouped merge — content and recurrence topology can come
///     from different snapshots, so the joined row must replace the single
///     whole-record snapshot currently visible to CloudKit.
///
/// In all of these cases CloudKit keeps one record per entity, so two receivers can
/// legally observe different envelope subsets / list states and end stuck-divergent
/// under the same version. The receiver whose merged row diverged closes the gap
/// by re-emitting a fresh-HLC upsert of the merged snapshot, the same convergence
/// move ``ListDeleteRehome/reenqueueRehomed(_:taskIds:mintVersion:deviceId:)``
/// makes for a re-homed task.
///
/// The HLC clock and local device identity live one layer up in the driver
/// (`SwiftLorvexCoreService.applyInbound`); this type only reports whether a
/// re-emit is warranted, and the driver mints the HLC and enqueues the snapshot.
///
/// The re-emit's fresh HLC can, in a one-round-trip window, overwrite a peer's
/// subsequent genuine edit that lands between the omitting envelope's version and
/// the re-emit's version — an accepted low-frequency trade-off with no cheap
/// mitigation. See `docs/design/SYNC_APPLY_SEMANTICS.md`, "Convergence re-emit".
public enum AbsencePreserveReemit {

  /// One absence-preserving child collection: the payload key that carries it and
  /// an `EXISTS` probe (bound with the parent entity id) for whether the entity
  /// currently holds any child rows.
  private struct Collection {
    let payloadKey: String
    let childExistsSQL: String
  }

  private static func collections(for entityType: EntityKind) -> [Collection] {
    switch entityType {
    case .currentFocus:
      return [
        Collection(
          payloadKey: "task_ids",
          childExistsSQL: "SELECT EXISTS(SELECT 1 FROM current_focus_items WHERE date = ?)")
      ]
    case .dailyReview:
      return [
        Collection(
          payloadKey: "linked_task_ids",
          childExistsSQL:
            "SELECT EXISTS(SELECT 1 FROM daily_review_task_links WHERE review_date = ?)"),
        Collection(
          payloadKey: "linked_list_ids",
          childExistsSQL:
            "SELECT EXISTS(SELECT 1 FROM daily_review_list_links WHERE review_date = ?)"),
      ]
    default:
      return []
    }
  }

  /// Whether a just-APPLIED upsert preserved child rows its payload omitted — the
  /// payload omits an absence-preserving collection key AND the entity currently
  /// holds at least one child row for it. Call only for an ``ApplyResult/applied``
  /// upsert (so `envelope.entityId` is the row that actually landed, not a
  /// redirect source). Returns `false` for non-upserts, unaffected entity types,
  /// and a malformed payload (handled elsewhere in the pipeline).
  static func preservedAbsentChildren(_ db: Database, envelope: SyncEnvelope) throws -> Bool {
    guard envelope.operation == .upsert else { return false }
    let cols = collections(for: envelope.entityType)
    if cols.isEmpty { return false }
    guard case .object(let obj)? = JSONValue.parse(envelope.payload) else { return false }
    for col in cols where obj[col.payloadKey] == nil {
      let has: Bool
      do {
        has =
          try Bool.fetchOne(db, sql: col.childExistsSQL, arguments: [envelope.entityId]) ?? false
      } catch { throw ApplyError.lift(error) }
      if has { return true }
    }
    return false
  }

  /// Whether a just-APPLIED `task` upsert landed in a different `list_id` than its
  /// payload NAMED — the per-device ``ApplyTask/resolveListId`` fallback rehomed
  /// it because the payload's list is tombstoned on this device. The merged row's
  /// list then differs from the envelope, so a peer that still holds the payload's
  /// list would keep the task there under the same version; re-emitting the
  /// resolved snapshot converges them. Scoped to a payload that NAMED a non-empty
  /// list_id (an omitted list_id carries no cross-peer intent to converge on).
  ///
  /// The payload's named `list_id` when the just-applied `task` upsert diverged
  /// from it (rehomed elsewhere), otherwise `nil`. Doubles as the dedup ledger key
  /// for the list-fallback re-emit.
  private static func divergedPayloadListId(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> String? {
    guard envelope.operation == .upsert, envelope.entityType == .task else { return nil }
    guard case .object(let obj)? = JSONValue.parse(envelope.payload) else { return nil }
    let payloadListId: String?
    switch obj["list_id"] {
    case .string(let s): payloadListId = s.isEmpty ? nil : s
    default: payloadListId = nil
    }
    guard let payloadListId else { return nil }
    let currentListId: String?
    do {
      currentListId = try String.fetchOne(
        db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [envelope.entityId])
    } catch { throw ApplyError.lift(error) }
    guard let currentListId else { return nil }
    return payloadListId != currentListId ? payloadListId : nil
  }

  /// Whether the calendar base-event grouped join produced a snapshot different
  /// from the envelope that triggered it. Occurrence decisions are whole-row LWW
  /// and never enter this path.
  private static func divergedCalendarBasePayload(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .calendarEvent,
      let local = try CalendarEventSyncRow.load(db, id: envelope.entityId), local.isBase,
      case .object(let incomingObject)? = JSONValue.parse(envelope.payload)
    else { return false }
    // A base event has no occurrence state. Treat an explicitly non-null value
    // as a decision even if a malformed caller bypassed contract validation.
    if incomingObject["occurrence_state"] != nil,
      incomingObject["occurrence_state"] != .null
    {
      return false
    }

    let current: JSONValue
    do {
      let known = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
      current = try PayloadShadow.mergePayloadWithShadowReporting(
        db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
        knownPayload: known
      ).payload
    } catch { throw ApplyError.lift(error) }
    do {
      return try SyncCanonicalize.canonicalizeJSON(current)
        != SyncCanonicalize.canonicalizeJSON(.object(incomingObject))
    } catch {
      throw ApplyError.invalidPayload(
        "calendar_event convergence comparison failed: \(error)")
    }
  }

  /// Whether the four-register task join produced a full snapshot different
  /// from the envelope that triggered it. CloudKit stores one record per task,
  /// so the joined value must be re-authored at a fresh transport HLC or a peer
  /// that observed only the triggering snapshot can remain permanently split.
  private static func divergedTaskPayload(
    _ db: Database, envelope: SyncEnvelope, normalizingListFallback: Bool = false
  ) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .task,
      case .object(var incoming)? = JSONValue.parse(envelope.payload)
    else { return false }
    let current: JSONValue
    do {
      let known = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
      current = try PayloadShadow.mergePayloadWithShadowReporting(
        db, entityType: envelope.entityType.asString, entityID: envelope.entityId,
        knownPayload: known
      ).payload
    } catch { throw ApplyError.lift(error) }
    // A tombstoned/missing payload list is intentionally rewritten to this
    // device's valid fallback. That one known difference belongs to the
    // `(task,payload_list_id)` one-shot ledger below, not the generic grouped-
    // register divergence arm. Normalize only that field for this comparison;
    // any other joined-register difference must still request an unledgered
    // convergence re-emit.
    if normalizingListFallback, case .object(let currentObject) = current,
      let currentListId = currentObject["list_id"]
    {
      incoming["list_id"] = currentListId
    }
    do {
      return try SyncCanonicalize.canonicalizeJSON(current)
        != SyncCanonicalize.canonicalizeJSON(.object(incoming))
    } catch {
      throw ApplyError.invalidPayload("task convergence comparison failed: \(error)")
    }
  }

  /// Whether the remove-wins cutover join produced a durable snapshot different
  /// from the triggering envelope. This is required even when the incoming
  /// `active` HLC is newer than an older local `deleted`: the row retains the
  /// higher clock but `deleted` remains absorbing, so CloudKit must receive one
  /// strict-successor full snapshot of that join.
  private static func divergedCalendarSeriesCutoverPayload(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> Bool {
    guard envelope.operation == .upsert,
      envelope.entityType == .calendarSeriesCutover,
      case .object(let incoming)? = JSONValue.parse(envelope.payload)
    else { return false }
    let current: JSONValue
    do {
      current = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: envelope.entityType.asString, entityId: envelope.entityId)
    } catch { throw ApplyError.lift(error) }
    do {
      return try SyncCanonicalize.canonicalizeJSON(current)
        != SyncCanonicalize.canonicalizeJSON(.object(incoming))
    } catch {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover convergence comparison failed: \(error)")
    }
  }

  /// Unified driver entry point: returns the merged row that needs a fresh-HLC
  /// snapshot re-emit, or `nil` when the row did not diverge from its envelope or
  /// a list-fallback re-emit was already claimed.
  ///
  /// Detection is deliberately side-effect free. The list-fallback arm is
  /// one-shot deduped by `sync_list_fallback_reemit_claims`, but the
  /// ledger must be written only AFTER the outbox enqueue succeeds. Otherwise a
  /// transient enqueue failure would burn the one re-emit attempt and strand the
  /// divergence permanently. Call ``recordConvergenceReemitEnqueued(_:target:)``
  /// after a successful enqueue.
  public static func convergenceReemitTarget(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> AbsenceReemitTarget? {
    if let target = try schemaEvolutionReemitTarget(
      db, envelope: envelope, appliedEntityId: envelope.entityId)
    {
      return target
    }
    if try divergedCalendarSeriesCutoverPayload(db, envelope: envelope) {
      return AbsenceReemitTarget(
        entityType: envelope.entityType.asString, entityId: envelope.entityId)
    }
    if try divergedCalendarBasePayload(db, envelope: envelope) {
      return AbsenceReemitTarget(
        entityType: envelope.entityType.asString, entityId: envelope.entityId)
    }
    let payloadListId = try divergedPayloadListId(db, envelope: envelope)
    if try divergedTaskPayload(
      db, envelope: envelope, normalizingListFallback: payloadListId != nil)
    {
      return AbsenceReemitTarget(
        entityType: envelope.entityType.asString, entityId: envelope.entityId)
    }
    if try preservedAbsentChildren(db, envelope: envelope) {
      return AbsenceReemitTarget(
        entityType: envelope.entityType.asString, entityId: envelope.entityId)
    }
    if let payloadListId {
      if try listFallbackReemitAlreadyClaimed(
        db, entityId: envelope.entityId, payloadListId: payloadListId)
      {
        return nil
      }
      return AbsenceReemitTarget(
        entityType: envelope.entityType.asString, entityId: envelope.entityId,
        listFallbackPayloadListId: payloadListId)
    }
    return nil
  }

  /// A full-snapshot successor required by rolling payload-schema evolution.
  ///
  /// The first arm handles a current runtime preserving fields it knows but an
  /// older envelope could not name. The second handles an older runtime carrying
  /// a still-opaque, higher-schema shadow across a legacy update. In both cases
  /// the local row differs from the one CloudKit currently stores; only a fresh
  /// dominating full snapshot lets a fresh/rebuilt peer recover the preserved
  /// value rather than materializing the legacy insert default.
  public static func schemaEvolutionReemitTarget(
    _ db: Database, envelope: SyncEnvelope, appliedEntityId: String
  ) throws -> AbsenceReemitTarget? {
    try schemaEvolutionReemitTarget(
      db, envelope: envelope, appliedEntityId: appliedEntityId,
      introductions: SyncPayloadEvolution.fieldIntroductions)
  }

  static func schemaEvolutionReemitTarget(
    _ db: Database, envelope: SyncEnvelope, appliedEntityId: String,
    introductions: [SyncPayloadFieldIntroduction]
  ) throws -> AbsenceReemitTarget? {
    guard envelope.operation == .upsert else { return nil }
    let knowsLaterField = SyncPayloadEvolution.hasFieldIntroduced(
      after: envelope.payloadSchemaVersion, for: envelope.entityType,
      in: introductions)
    let shadow: PayloadShadow.Row?
    do {
      shadow = try PayloadShadow.getShadow(
        db, entityType: envelope.entityType.asString, entityID: appliedEntityId)
    } catch { throw ApplyError.lift(error) }
    let preservedHigherSchemaShadow =
      shadow.map { $0.payloadSchemaVersion > Int(envelope.payloadSchemaVersion) } ?? false
    guard knowsLaterField || preservedHigherSchemaShadow else { return nil }
    return AbsenceReemitTarget(
      entityType: envelope.entityType.asString, entityId: appliedEntityId)
  }

  /// The merge WINNER a redirect-remapped habit upsert just CHANGED, as a
  /// re-emit target — or `nil` when no winner re-emit is warranted.
  ///
  /// `habits` is the only aggregate whose merge eligibility predicate is MUTABLE:
  /// the partial `UNIQUE(lookup_key) WHERE archived = 0`, so a loser can leave the
  /// index by being archived. A device that pulled the loser while it was active
  /// MERGES it into the winner (loser→winner redirect); a device that pulled only
  /// the archived loser sees no collision and never merges. When a later
  /// loser-addressed upsert is redirect-remapped onto the winner — an
  /// ``ApplyResult/remapped(fromEntityId:toEntityId:)`` upsert, which lands only
  /// after strictly winning LWW against the target, so it always changed the
  /// winner's row (e.g. flipped its `archived` flag / content to the loser's) —
  /// the non-merging peer never replicates that change and stays divergent.
  /// Re-emitting the winner's snapshot at a fresh HLC (the same convergence move
  /// ``convergenceReemitTarget(_:envelope:)`` makes for an absence-preserving
  /// merge) pulls the fleet back together; the merge itself cannot, because its
  /// stamped winner version is wire-silent.
  ///
  /// Scoped to habit upserts: every other redirect-merge (tag, memory, reminder policy)
  /// keys on IMMUTABLE identity, so all peers observe the same
  /// collision and converge without a re-emit. `toEntityId` is the redirect
  /// terminus (the merge winner) carried by the ``ApplyResult/remapped`` outcome.
  public static func remappedMergeWinnerReemitTarget(
    _ db: Database, envelope: SyncEnvelope, toEntityId: String
  ) throws -> AbsenceReemitTarget? {
    if let target = try schemaEvolutionReemitTarget(
      db, envelope: envelope, appliedEntityId: toEntityId)
    {
      return target
    }
    guard envelope.operation == .upsert, envelope.entityType == .habit else { return nil }
    return AbsenceReemitTarget(entityType: envelope.entityType.asString, entityId: toEntityId)
  }

  /// Record the one-shot list-fallback ledger after its convergence snapshot has
  /// been enqueued successfully. Absence-preserve targets have no ledger.
  public static func recordConvergenceReemitEnqueued(
    _ db: Database, target: AbsenceReemitTarget
  ) throws {
    guard let payloadListId = target.listFallbackPayloadListId else { return }
    try claimListFallbackReemit(
      db, entityId: target.entityId, payloadListId: payloadListId)
  }

  /// Whether the durable one-shot list-fallback re-emit ledger already contains
  /// this `(entity_id, payload_list_id)` pair.
  private static func listFallbackReemitAlreadyClaimed(
    _ db: Database, entityId: String, payloadListId: String
  ) throws -> Bool {
    do {
      return
        try Bool.fetchOne(
          db,
          sql: """
            SELECT EXISTS(
                SELECT 1 FROM sync_list_fallback_reemit_claims
                 WHERE task_id = ? AND payload_list_id = ?
            )
            """,
          arguments: [entityId, payloadListId]) ?? false
    } catch { throw ApplyError.lift(error) }
  }

  private static func claimListFallbackReemit(
    _ db: Database, entityId: String, payloadListId: String
  ) throws {
    do {
      try db.execute(
        sql: """
          INSERT OR IGNORE INTO sync_list_fallback_reemit_claims
            (task_id, payload_list_id)
          VALUES (?, ?)
          """,
        arguments: [entityId, payloadListId])
    } catch { throw ApplyError.lift(error) }
  }
}
