import GRDB
import LorvexDomain

extension FutureRecordHold {
  /// Fulfill a set of preserved local intents in deterministic dependency order.
  ///
  /// Both inbound sync and the generic local-write pending-inbox finalizer call
  /// this one batch surface. Upserts establish parents before children; deletes
  /// remove children before parents; permanent redirects run last after every
  /// possible live or terminal target has been established. The complete
  /// comparator avoids relying on Swift sort stability if corrupt or legacy
  /// state ever surfaces duplicate replay identities.
  @discardableResult
  public static func fulfillLocalIntentReplays(
    _ db: Database, replays: [LocalIntentReplay],
    registry: EntityApplierRegistry,
    mintVersion: @escaping (_ knownVersionFloor: Hlc?) -> String,
    deviceId: String
  ) throws -> Set<EntityKind> {
    var changedKinds: Set<EntityKind> = []
    for replay in try orderedLocalIntentReplays(db, replays: replays) {
      changedKinds.formUnion(
        try fulfillLocalIntentReplay(
          db, replay: replay, registry: registry,
          mintVersion: mintVersion, deviceId: deviceId))
    }
    return changedKinds
  }

  static func orderedLocalIntentReplays(
    _ db: Database, replays: [LocalIntentReplay]
  ) throws -> [LocalIntentReplay] {
    let topologicalIndex = Dictionary(
      uniqueKeysWithValues: EntityKind.topologicalEntityOrder.enumerated().map {
        ($1, $0)
      })
    let ordered = replays.sorted { lhs, rhs in
      let lhsPhase = localIntentReplayPhase(lhs.intent)
      let rhsPhase = localIntentReplayPhase(rhs.intent)
      if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }

      let lhsIndex = topologicalIndex[lhs.intent.entityType.asString] ?? Int.max
      let rhsIndex = topologicalIndex[rhs.intent.entityType.asString] ?? Int.max
      if lhsIndex != rhsIndex {
        return lhsPhase == 1 ? lhsIndex > rhsIndex : lhsIndex < rhsIndex
      }
      if lhs.intent.entityType != rhs.intent.entityType {
        return lhs.intent.entityType.asString < rhs.intent.entityType.asString
      }
      if lhs.intent.entityId != rhs.intent.entityId {
        return lhs.intent.entityId < rhs.intent.entityId
      }
      if lhs.intent.version != rhs.intent.version {
        return lhs.intent.version < rhs.intent.version
      }
      if lhs.remoteFloor != rhs.remoteFloor {
        return lhs.remoteFloor < rhs.remoteFloor
      }
      if lhs.intent.operation != rhs.intent.operation {
        return lhs.intent.operation.asString < rhs.intent.operation.asString
      }
      if lhs.intent.payloadSchemaVersion != rhs.intent.payloadSchemaVersion {
        return lhs.intent.payloadSchemaVersion < rhs.intent.payloadSchemaVersion
      }
      if lhs.intent.payload != rhs.intent.payload {
        return lhs.intent.payload.utf8.lexicographicallyPrecedes(rhs.intent.payload.utf8)
      }
      return lhs.intent.deviceId.utf8.lexicographicallyPrecedes(rhs.intent.deviceId.utf8)
    }

    // Delete envelopes normally retain only their HLC. Capture the materialized
    // lineage before any replay can re-root a child or remove its parent.
    var deleteParentById: [String: String] = [:]
    for replay in ordered
    where replay.intent.entityType == .task && replay.intent.operation == .delete
    {
      if let parentId: String = try String.fetchOne(
        db, sql: "SELECT spawned_from FROM tasks WHERE id = ?",
        arguments: [replay.intent.entityId])
      {
        deleteParentById[replay.intent.entityId] = parentId
      }
    }

    do {
      return try TaskLineageReplayOrder.reorder(
        ordered, operations: [.upsert, .delete], envelope: { $0.intent }
      ) { replay in
        if replay.intent.operation == .delete {
          return deleteParentById[replay.intent.entityId]
        }
        guard case .object(let payload)? = JSONValue.parse(replay.intent.payload),
          case .string(let parentId)? = payload["spawned_from"]
        else { return nil }
        return parentId
      }
    } catch let error as TaskLineageReplayOrderError {
      switch error {
      case .duplicateIdentity(let entityId, let operation):
        throw ApplyError.invalidPayload(
          "future local task \(operation.asString) replay duplicates identity \(entityId)")
      case .cycle(let entityId, let operation):
        throw ApplyError.invalidPayload(
          "future local task \(operation.asString) replay contains a spawned_from cycle at "
            + entityId)
      }
    }
  }

  private static func localIntentReplayPhase(_ envelope: SyncEnvelope) -> Int {
    if envelope.entityType == .entityRedirect { return 2 }
    return envelope.operation == .delete ? 1 : 0
  }
}
