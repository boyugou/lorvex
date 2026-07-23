import LorvexDomain

/// Entity domains whose canonical rows can change while applying one envelope.
///
/// Most mutations affect only their addressed kind. A permanent redirect is a
/// cross-kind control record: applying it can merge/delete the underlying tag,
/// habit, memory, or reminder-policy aggregate as well as updating the redirect
/// ledger. Hosts must invalidate both domains after the same transaction.
public enum SyncMutationImpact {
  public static func affectedEntityTypes(
    for envelope: SyncEnvelope
  ) throws -> Set<EntityKind> {
    var kinds: Set<EntityKind> = [envelope.entityType]
    guard envelope.entityType == .entityRedirect else { return kinds }
    let payload = try EntityRedirect.decodePayload(
      wireEntityId: envelope.entityId, payload: envelope.payload)
    kinds.insert(payload.sourceType)
    return kinds
  }
}
