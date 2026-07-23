import Foundation
import GRDB
import LorvexDomain

/// Durable entity-redirect chain walker + payload identity-rewrite helpers.
///
/// Both the apply entry and shadow promotion chase the same
/// `sync_entity_redirects` chain when resolving an inbound
/// envelope to its current target, and the per-hop payload-FK rewrite uses the
/// same field table for both call sites.
enum ApplyRedirect {

  /// A single hop along a permanent redirect chain.
  struct RedirectHop: Sendable, Equatable {
    /// The entity_type the hop departed from. Redirects are always same-type.
    var fromEntityType: String
    var fromEntityId: String
    /// The entity id the hop landed on.
    var toEntityId: String
    /// The alias record's HLC version. Carried so callers can attribute downstream
    /// rows to the local device when the merge was locally authored.
    var version: String
  }

  /// Result of chasing a redirect chain: the final `(entityType, entityId)` to
  /// apply against and the per-hop log.
  struct ChaseResult: Sendable, Equatable {
    var finalType: String
    var finalId: String
    var hops: [RedirectHop]
  }

  /// Walk the permanent `sync_entity_redirects` chain starting from
  /// `(initialEntityType, initialEntityId)`. Returns the chain terminus (or the
  /// initial pair when no alias exists) plus the per-hop log.
  ///
  /// Bounded by ``redirectChainCap``. After consuming the cap, does one more
  /// probe — if the terminal id still has a redirect, surfaces
  /// ``ApplyError/entityRedirectChainTooDeep`` so the apply never lands on an
  /// intermediate hop. Cycles surface as ``ApplyError/entityRedirectCycle``.
  /// Every hop is same-type by schema and trust-boundary validation.
  static func chaseRedirectChain(
    _ db: Database, initialEntityType: String, initialEntityId: String
  ) throws -> ChaseResult {
    switch EntityKind.parse(initialEntityType) {
    case let .some(kind) where kind.isSyncableKind:
      break
    default:
      throw ApplyError.unknownEntityType(initialEntityType)
    }
    var currentType = initialEntityType
    var currentId = initialEntityId
    var hops: [RedirectHop] = []
    // Seed the visited set with the INITIAL id so a self-redirect in the very
    // first hop is caught immediately.
    var visited: [(String, String)] = [(currentType, currentId)]

    for _ in 0..<redirectChainCap {
      let redirect: EntityRedirect.Record?
      do {
        redirect = try EntityRedirect.get(db, sourceType: currentType, sourceId: currentId)
      } catch { throw ApplyError.lift(error) }
      guard let redirect else {
        return ChaseResult(finalType: currentType, finalId: currentId, hops: hops)
      }
      let redirectId = redirect.targetId
      let nextType = currentType
      let nextId = remapEntityId(
        originalId: currentId, oldPart: redirect.sourceId, newPart: redirectId,
        entityType: currentType)
      if visited.contains(where: { $0.0 == nextType && $0.1 == nextId }) {
        throw ApplyError.entityRedirectCycle(entityType: currentType, entityId: currentId)
      }
      let fromType = currentType
      let fromId = currentId
      currentType = nextType
      currentId = nextId
      visited.append((currentType, currentId))
      hops.append(
        RedirectHop(
          fromEntityType: fromType, fromEntityId: fromId, toEntityId: nextId,
          version: redirect.version))
    }

    // Cap exhausted. Probe once more so a chain longer than the cap surfaces as
    // a typed error rather than landing the apply on an intermediate id.
    do {
      if try EntityRedirect.get(db, sourceType: currentType, sourceId: currentId) != nil {
        throw ApplyError.entityRedirectChainTooDeep(
          entityType: initialEntityType, entityId: initialEntityId,
          chainLength: hops.count, terminalId: currentId)
      }
    } catch let e as ApplyError {
      throw e
    } catch { throw ApplyError.lift(error) }
    return ChaseResult(finalType: currentType, finalId: currentId, hops: hops)
  }

  /// Parent entity types of a composite edge's two halves, or `nil` when
  /// `entityType` is not a composite edge. The right entry is `nil` when the
  /// right half is not an entity reference (`habit_completion`'s right half is a
  /// `YYYY-MM-DD` date, which never merges/redirects).
  private static func compositeEdgeParentTypes(_ entityType: String) -> (String, String?)? {
    switch entityType {
    case EdgeName.taskTag: return (EntityName.task, EntityName.tag)
    case EdgeName.taskDependency: return (EntityName.task, EntityName.task)
    case EdgeName.taskCalendarEventLink: return (EntityName.task, EntityName.calendarEvent)
    case EdgeName.habitCompletion: return (EntityName.habit, nil)
    default: return nil
    }
  }

  /// Chase one composite-edge half through its parent's redirect chain, returning
  /// the surviving parent id. A cross-type chain terminus cannot recompose into an
  /// edge half of the same kind, so it is treated as "no remap" (the id is
  /// returned unchanged), mirroring ``remapMissingDependency``'s same-type guard.
  private static func chaseParentHalf(
    _ db: Database, parentType: String, id: String
  ) throws -> String {
    let chase = try chaseRedirectChain(db, initialEntityType: parentType, initialEntityId: id)
    return chase.finalType == parentType ? chase.finalId : id
  }

  /// Remap a composite-edge envelope through its parents' permanent redirects.
  ///
  /// A composite edge id `left:right` names two parent entities (e.g. `task_tag`
  /// = `task_id:tag_id`). When a parent is merged, only the PARENT carries a
  /// durable alias — the schema's redirect source-type CHECK makes an edge-typed
  /// redirect row unstorable, so the edge id itself never resolves. This chases
  /// each half's parent redirect chain and, when either half moves, returns a
  /// remapped envelope addressed at the recomposed edge id with the payload's FK
  /// identity fields rewritten to agree. Returns `nil` when neither half moves or
  /// the id is malformed (left for the normal path to reject). Halves whose
  /// parent kind cannot carry redirects (`task`, `calendar_event` — outside the
  /// schema's source-type CHECK) chase an always-empty chain and return
  /// unchanged; the traversal stays uniform rather than special-casing them.
  ///
  /// Applied to BOTH upsert and delete before the tombstone/LWW gate so an edge
  /// operation converges onto the surviving parent regardless of arrival order:
  /// an upsert lands on the winner edge; a delete removes the winner edge (rather
  /// than no-op'ing on the vanished loser id and leaving the remapped edge to
  /// resurrect the deleted relationship). The payload rewrite is load-bearing for
  /// the upsert path — FK preflight rejects an edge whose payload FK fields
  /// disagree with the (remapped) entity_id — and harmless for the identity-only
  /// delete path.
  static func remapCompositeEdgeThroughParentRedirects(
    _ db: Database, envelope: SyncEnvelope
  ) throws -> SyncEnvelope? {
    let entityTypeStr = envelope.entityType.asString
    guard let (leftType, rightType) = compositeEdgeParentTypes(entityTypeStr) else {
      return nil
    }
    let left: String
    let right: String
    switch CompositeEdge.splitCompositeEdgeId(envelope.entityId) {
    case let .success(pair):
      (left, right) = pair
    case .failure:
      return nil
    }

    let newLeft = try chaseParentHalf(db, parentType: leftType, id: left)
    let newRight: String
    if let rightType {
      newRight = try chaseParentHalf(db, parentType: rightType, id: right)
    } else {
      newRight = right
    }
    if newLeft == left && newRight == right { return nil }

    var remapped = envelope
    remapped.entityId = "\(newLeft):\(newRight)"

    if var payloadValue = JSONValue.parse(envelope.payload) {
      if newLeft != left {
        _ = remapPayloadIdentityFields(
          entityType: entityTypeStr, payload: &payloadValue, originalId: left, targetId: newLeft)
      }
      if newRight != right {
        _ = remapPayloadIdentityFields(
          entityType: entityTypeStr, payload: &payloadValue, originalId: right, targetId: newRight)
      }
      if let recanonical = try? SyncCanonicalize.canonicalizeJSON(payloadValue) {
        remapped.payload = recanonical
      }
    }
    return remapped
  }

  /// Remap an entity_id by replacing the tombstoned part with the redirect
  /// target. Composite keys (`"a:b"`) replace only the exact-match segment;
  /// simple keys return the redirect target directly.
  ///
  /// Asserts in debug builds that natural-key entity types never reach the
  /// redirect branch — their identity is content-derived and never participates
  /// in merge-redirect rewriting.
  static func remapEntityId(
    originalId: String, oldPart: String, newPart: String, entityType: String?
  ) -> String {
    if let et = entityType {
      assert(
        !(EntityKind.parse(et)?.isNaturalKey ?? false),
        "remapEntityId called for natural-key entity_type \(et) (original=\(originalId), "
          + "oldPart=\(oldPart), newPart=\(newPart)) — natural keys must not enter the "
          + "redirect branch")
    }
    if let colon = originalId.firstIndex(of: ":") {
      let left = String(originalId[originalId.startIndex..<colon])
      let right = String(originalId[originalId.index(after: colon)...])
      let newLeft = left == oldPart ? newPart : left
      let newRight = right == oldPart ? newPart : right
      return "\(newLeft):\(newRight)"
    }
    return newPart
  }

  /// Rewrite payload-FK fields that name the loser identity alongside the
  /// envelope's `entity_id` when a redirect chase fires. Returns `true` when at
  /// least one field actually changed. The match table is the source of truth
  /// for both the apply redirect chase and the pending-inbox dependency remap.
  ///
  /// `payload` is mutated in place; the caller re-serializes.
  static func remapPayloadIdentityFields(
    entityType: String, payload: inout JSONValue, originalId: String, targetId: String
  ) -> Bool {
    guard case var .object(map) = payload else { return false }
    guard let kind = EntityKind.parse(entityType) else { return false }
    let fields: [String]
    switch kind {
    case .task, .tag, .list, .habit, .calendarEvent,
      .memory, .dailyReview, .currentFocus, .focusSchedule, .preference:
      fields = ["id"]
    case .calendarSeriesCutover:
      return false
    case .taskTag: fields = ["task_id", "tag_id"]
    case .taskDependency: fields = ["task_id", "depends_on_task_id"]
    case .taskCalendarEventLink: fields = ["task_id", "calendar_event_id"]
    case .habitCompletion: fields = ["habit_id", "completed_date"]
    case .taskReminder, .taskChecklistItem: fields = ["task_id"]
    case .habitReminderPolicy: fields = ["habit_id"]
    case .aiChangelog, .entityRedirect, .deviceState, .importSession:
      return false
    }
    var changed = false
    for field in fields {
      if case let .string(current)? = map[field], current == originalId {
        map[field] = .string(targetId)
        changed = true
      }
    }
    if changed { payload = .object(map) }
    return changed
  }
}
