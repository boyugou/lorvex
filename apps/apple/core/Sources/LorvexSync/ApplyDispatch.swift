import Foundation
import GRDB
import LorvexDomain

/// Entity-type dispatch seam for the apply pipeline.
///
/// `apply_envelope` resolves an envelope's `entity_type` to a per-entity applier
/// and routes the upsert / delete through it. Each per-entity applier conforms
/// to ``EntityApplier`` and registers itself in an ``EntityApplierRegistry``.
/// This file lands the protocol, the typed outcome, the registry injection
/// point, and the dispatch wrapper (including the post-handler LWW re-check) so
/// the per-entity slices plug in without touching the dispatcher.
///
/// Every syncable `entity_type` now resolves to a real applier in
/// ``EntityApplierRegistry/defaultEntityAppliers()``; only local-only /
/// non-synced kinds (e.g. `device_state`) fall through to
/// ``ApplyError/unknownEntityType(_:)``.

/// Outcome of dispatching a single envelope to its handler.
///
/// Distinguishes "delete fully applied / intentionally skipped" from "delete
/// refused by the handler's in-handler LWW gate". The caller in `apply_envelope`
/// uses the variant to decide whether to create the tombstone row downstream.
public enum EntityApplyOutcome: Sendable, Equatable {
  /// Upsert applied, delete that removed the row, idempotent late-replay delete,
  /// or an intentional in-handler skip — all need the tombstone written.
  case applied
  /// An append-only audit upsert was intentionally not stored because its
  /// timestamp falls outside the receiver's retention frontier. The applier has
  /// already queued an exact-zone CloudKit physical delete; treating this as an
  /// ordinary applied no-op would strand full content in CloudKit.
  case upsertRejectedByRetention
  /// The in-handler LWW gate refused the SQL DELETE because the surviving local
  /// row's HLC dominates the envelope's. `localVersion` carries the row's
  /// pre-handler version so the caller renders the conflict-log row without a
  /// second SELECT. The caller does NOT mint a tombstone for this outcome.
  case lwwRejected(localVersion: String)
  /// An aggregate-level invariant guard refused the in-handler DELETE while
  /// leaving the row alive (the at-least-one-list invariant). The caller defers
  /// the envelope to the pending inbox instead of writing a tombstone.
  case deleteSkippedByInvariant(invariant: String)
  /// A peer delete targeted the permanent canonical inbox. The row survives and
  /// no tombstone is minted; the outer apply flow surfaces a typed repair
  /// obligation so the host replaces the shared delete record with a dominating
  /// inbox upsert before advancing its checkpoint.
  case requiredInboxDeleteRejected
  /// A peer attempted the invalid physical Delete operation against an
  /// upsert-only calendar-series boundary. The durable row survives and the
  /// host must replace the shared Delete with a dominating full upsert.
  case requiredCutoverDeleteRejected
  /// The applier performed deterministic local cleanup that must be propagated
  /// to shared records before the inbound checkpoint can advance.
  case repairRequired(ApplyRepairObligation)
  /// The delete named a local-only entity (a local-only preference key) that
  /// never round-trips through sync, so the handler applied nothing and the row —
  /// if any — survives. The caller skips WITHOUT writing a tombstone: a tombstone
  /// over a surviving local-only row would break the "tombstone ⇒ row dead"
  /// invariant. Unlike ``deleteSkippedByInvariant``, this is NOT deferred — the
  /// local-only condition never relaxes, so a replay would loop forever.
  case deleteSkippedLocalOnly
}

/// Per-entity applier protocol. Each syncable entity type's applier conforms to
/// this and registers in an ``EntityApplierRegistry``. The protocol collapses
/// per-entity dispatch into one
/// seam: the conformer owns its own upsert / delete SQL, in-handler LWW gate,
/// and (where applicable) invariant gate, returning the typed
/// ``EntityApplyOutcome``.
///
/// `applyTs` is the once-per-envelope captured wall clock threaded through so
/// cascade-tombstone helpers and merge conflict-log writes inside the handler
/// share one atomic moment of apply.
public protocol EntityApplier: Sendable {
  /// The entity types this applier handles (canonical `entity_type` strings).
  var handledEntityTypes: [String] { get }

  /// Apply an upsert. Conformers install their own LWW gate using `tieBreak`.
  func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome

  /// Apply a delete. Conformers return the typed outcome so the dispatcher can
  /// surface in-handler LWW / invariant rejections.
  func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome
}

/// Registry of per-entity appliers, keyed by canonical `entity_type`. The
/// injection point the per-entity slices populate. Empty in the foundation
/// slice: dispatch against an empty registry throws
/// ``ApplyError/unknownEntityType(_:)`` for every type, which is the correct
/// behavior until the per-entity appliers land.
public struct EntityApplierRegistry: Sendable {
  private let byType: [String: any EntityApplier]

  public init(appliers: [any EntityApplier] = []) {
    var map: [String: any EntityApplier] = [:]
    for applier in appliers {
      for type in applier.handledEntityTypes {
        map[type] = applier
      }
    }
    self.byType = map
  }

  func lookup(_ entityType: String) -> (any EntityApplier)? { byType[entityType] }
}

extension EntityApplierRegistry {
  /// The per-entity appliers landed so far. Per-entity slices append their
  /// applier here as they land; the dispatcher resolves any `entity_type` not in
  /// this set to ``ApplyError/unknownEntityType(_:)``.
  ///
  /// Every syncable entity type's applier is registered here: the aggregate
  /// roots (`task`, `list`, `habit`, `tag` with duplicate-tag
  /// merge, `calendar_event` with attendee reconciliation, `memory`,
  /// `preference`, `ai_changelog`), the day-scoped aggregates (`current_focus`,
  /// `focus_schedule`, `daily_review`), the four composite edges (`task_tag`,
  /// `task_calendar_event_link`, `habit_completion`, and
  /// `task_dependency` with its cycle-break upsert), and the independent
  /// children (`task_reminder`, `task_checklist_item`, `habit_reminder_policy`).
  /// The recurrence-instance-key dedup tail runs inside `TaskApplier`'s upsert,
  /// not as a standalone applier.
  public static func defaultEntityAppliers() -> [any EntityApplier] {
    [
      TaskApplier(), ListApplier(), HabitApplier(), TagApplier(),
      TaskTagApplier(), TaskCalendarEventLinkApplier(), HabitCompletionApplier(),
      TaskDependencyApplier(),
      TaskReminderApplier(), TaskChecklistItemApplier(),
      HabitReminderPolicyApplier(),
      CalendarEventApplier(),
      CalendarSeriesCutoverApplier(),
      CurrentFocusApplier(), FocusScheduleApplier(), DailyReviewApplier(),
      MemoryApplier(), PreferenceApplier(),
      ChangelogApplier(),
    ]
  }
}

enum ApplyDispatch {
  /// Dispatch a single envelope to its registered applier. Returns the typed
  /// ``EntityApplyOutcome``. For delete envelopes whose applier does not surface
  /// a typed `lwwRejected`/`deleteSkippedByInvariant` outcome, the dispatcher
  /// pre-reads the local row's version, runs the applier, then re-checks: if the
  /// row still exists at a strictly greater version, the in-handler SQL gate
  /// refused the DELETE and we return `lwwRejected`.
  ///
  /// `defaultEntityAppliers()` populates the registry for every entity kind, so
  /// a dispatch resolves to the matching applier; an unrecognized kind returns
  /// ``ApplyError/unknownEntityType(_:)``.
  static func dispatch(
    _ db: Database, registry: EntityApplierRegistry, envelope: SyncEnvelope,
    tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let id = envelope.entityId
    let isDelete = envelope.operation == .delete

    guard let applier = registry.lookup(envelope.entityType.asString) else {
      throw ApplyError.unknownEntityType(envelope.entityType.asString)
    }

    if !isDelete {
      // A corrupt (unparseable) local version would make the handler's in-SQL
      // `:version <op> version` byte-compare gate silently refuse this canonical
      // upsert whenever the taint lex-sorts above canonical HLCs (letters sort
      // above digits), leaving the row permanently deaf to inbound sync while
      // apply still reports `.applied`. The outer LWW gate already admitted the
      // envelope (canonical dominates non-canonical under the canonical-preferring
      // policy); reset the taint (and any calendar clocks constrained beneath
      // it) to the zero HLC so the byte-compare gate agrees and the canonical
      // envelope lands + re-stamps the row. No-op for
      // absent / already-canonical local versions; deletes are excluded (they keep
      // the taint-refuses-delete safety in `evaluateDeleteLww`).
      try ApplyLww.resetCorruptLocalVersion(
        db, entityType: envelope.entityType.asString, entityId: id)
      return try applier.applyUpsert(db, envelope: envelope, tieBreak: tieBreak, applyTs: applyTs)
    }

    // Snapshot the local row's version before the delete runs so the
    // post-handler re-check can tell "applied" from "silently LWW-rejected".
    let preDeleteVersion = try ApplyLww.getLocalVersion(
      db, entityType: envelope.entityType.asString, entityId: id)

    let outcome = try applier.applyDelete(db, envelope: envelope, applyTs: applyTs)
    // If the applier already surfaced a typed early-return, propagate it.
    if case .applied = outcome {
      // Fall through to the post-handler re-check.
    } else {
      return outcome
    }

    if let postOutcome = try postHandlerLwwOutcome(
      db, envelope: envelope, id: id, preDeleteVersion: preDeleteVersion)
    {
      return postOutcome
    }
    return .applied
  }

  /// Post-handler LWW-rejection detection. Meaningful only when (1) a delete
  /// envelope targeted a versioned row, (2) a local row existed before the
  /// handler ran, (3) the local row STILL exists after the handler ran at a
  /// strictly greater version than the envelope's — meaning the handler's
  /// `:version >= version` SQL predicate refused the DELETE.
  ///
  /// Adopts parse-then-typed-compare with byte fallback. A tainted local row
  /// equal to its pre-version that the SQL byte-compare refused surfaces as
  /// `lwwRejected` so the caller does not mint a tombstone over a still-live
  /// row.
  static func postHandlerLwwOutcome(
    _ db: Database, envelope: SyncEnvelope, id: String, preDeleteVersion: String?
  ) throws -> EntityApplyOutcome? {
    guard let preVersion = preDeleteVersion else { return nil }
    guard
      let postVersion = try ApplyLww.getLocalVersion(
        db, entityType: envelope.entityType.asString, entityId: id)
    else {
      return nil
    }
    let postParse = try? Hlc.parseCanonical(postVersion)
    let preParse = try? Hlc.parseCanonical(preVersion)
    let postIsStrictlyNewer: Bool
    if let postHlc = postParse {
      postIsStrictlyNewer = postHlc > envelope.version
    } else {
      // Tainted local row vs canonical envelope. Sub-case A: both unparseable
      // AND equal → the SQL byte-compare refused the DELETE; surface
      // lwwRejected. Otherwise the row's shape changed mid-apply → let the
      // tombstone proceed.
      if preParse == nil && postVersion == preVersion {
        return .lwwRejected(localVersion: postVersion)
      }
      postIsStrictlyNewer = false
    }
    if postIsStrictlyNewer && postVersion == preVersion {
      return .lwwRejected(localVersion: postVersion)
    }
    return nil
  }
}
