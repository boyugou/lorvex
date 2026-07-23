import LorvexDomain

enum TaskLineageReplayOrderError: Error, Equatable {
  case duplicateIdentity(entityId: String, operation: SyncOperation)
  case cycle(entityId: String, operation: SyncOperation)
}

enum TaskLineageReplayOrder {
  static func reorder<Item>(
    _ ordered: [Item], operations: [SyncOperation],
    envelope: (Item) -> SyncEnvelope,
    parentIdForItem: (Item) throws -> String?
  ) throws -> [Item] {
    var result = ordered
    for operation in operations {
      result = try reorder(
        result, operation: operation, envelope: envelope,
        parentIdForItem: parentIdForItem)
    }
    return result
  }

  private static func reorder<Item>(
    _ ordered: [Item], operation: SyncOperation,
    envelope: (Item) -> SyncEnvelope,
    parentIdForItem: (Item) throws -> String?
  ) throws -> [Item] {
    let slots = ordered.indices.filter {
      let value = envelope(ordered[$0])
      return value.entityType == .task && value.operation == operation
    }
    guard !slots.isEmpty else { return ordered }

    let tasks = slots.map { ordered[$0] }
    var indexById: [String: Int] = [:]
    for (index, task) in tasks.enumerated() {
      let id = envelope(task).entityId
      guard indexById.updateValue(index, forKey: id) == nil else {
        throw TaskLineageReplayOrderError.duplicateIdentity(
          entityId: id, operation: operation)
      }
    }

    var successors = Array(repeating: [Int](), count: tasks.count)
    var indegree = Array(repeating: 0, count: tasks.count)
    for (childIndex, task) in tasks.enumerated() {
      guard let parentId = try parentIdForItem(task),
        let parentIndex = indexById[parentId]
      else { continue }
      let edge = operation == .delete
        ? (source: childIndex, target: parentIndex)
        : (source: parentIndex, target: childIndex)
      successors[edge.source].append(edge.target)
      indegree[edge.target] += 1
    }

    func lexicalOrder(_ lhs: Int, _ rhs: Int) -> Bool {
      envelope(tasks[lhs]).entityId < envelope(tasks[rhs]).entityId
    }
    var ready = tasks.indices.filter { indegree[$0] == 0 }.sorted(by: lexicalOrder)
    var indices: [Int] = []
    indices.reserveCapacity(tasks.count)
    while !ready.isEmpty {
      let next = ready.removeFirst()
      indices.append(next)
      for successor in successors[next].sorted(by: lexicalOrder) {
        indegree[successor] -= 1
        if indegree[successor] == 0 {
          ready.append(successor)
          ready.sort(by: lexicalOrder)
        }
      }
    }
    guard indices.count == tasks.count else {
      let blockedId = tasks.indices
        .filter { indegree[$0] > 0 }
        .map { envelope(tasks[$0]).entityId }
        .min() ?? "unknown"
      throw TaskLineageReplayOrderError.cycle(
        entityId: blockedId, operation: operation)
    }

    var result = ordered
    for (slot, taskIndex) in zip(slots, indices) {
      result[slot] = tasks[taskIndex]
    }
    return result
  }
}

extension AuthoritativeSnapshot {
  /// Deterministic replay order for post-session local intent.
  ///
  /// `spawned_from` is not a relational FK: deleting an occurrence deliberately
  /// re-roots an edited successor. It is nevertheless a causal ordering edge
  /// when both exact task Upserts are present in this one captured replay batch.
  /// Materialize such a parent before its successor so the rollover preflight
  /// can observe the parent's matching authorization clock. Parents absent from
  /// this batch, and task Deletes, create no edge here.
  static func orderedPostSessionLocalIntents(
    _ intents: [AuthoritativeSnapshotLocalIntent]
  ) throws -> [AuthoritativeSnapshotLocalIntent] {
    let topoIndex = Dictionary(
      uniqueKeysWithValues: EntityKind.topologicalEntityOrder.enumerated().map { ($1, $0) })
    let ordered = intents.sorted { lhs, rhs in
      let lhsPhase = postSessionReplayPhase(lhs.envelope)
      let rhsPhase = postSessionReplayPhase(rhs.envelope)
      if lhsPhase != rhsPhase { return lhsPhase < rhsPhase }
      let li = topoIndex[lhs.envelope.entityType.asString] ?? Int.max
      let ri = topoIndex[rhs.envelope.entityType.asString] ?? Int.max
      if li != ri { return lhsPhase == 1 ? li > ri : li < ri }
      if lhs.envelope.entityId != rhs.envelope.entityId {
        return lhs.envelope.entityId < rhs.envelope.entityId
      }
      return lhs.envelope.version < rhs.envelope.version
    }

    do {
      return try TaskLineageReplayOrder.reorder(
        ordered, operations: [.upsert], envelope: { $0.envelope }
      ) { intent in
        guard case .object(let payload)? = JSONValue.parse(intent.envelope.payload),
          case .string(let parentId)? = payload["spawned_from"]
        else { return nil }
        return parentId
      }
    } catch let error as TaskLineageReplayOrderError {
      switch error {
      case .duplicateIdentity(let entityId, _):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: EntityName.task, entityId: entityId,
          reason: "duplicate post-session task replay identity")
      case .cycle(let entityId, _):
        throw AuthoritativeSnapshotError.applyRejected(
          entityType: EntityName.task, entityId: entityId,
          reason: "post-session task replay contains a spawned_from cycle")
      }
    }
  }

  private static func postSessionReplayPhase(_ envelope: SyncEnvelope) -> Int {
    if envelope.entityType == .entityRedirect { return 2 }
    return envelope.operation == .delete ? 1 : 0
  }
}
