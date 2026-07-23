import GRDB
import LorvexDomain

/// The participant state available to an entity-specific adapter while a
/// cross-id aggregate collision is still fully reversible.
///
/// The engine has already selected the canonical identity and the whole-row
/// content reference, but no content carry or identity deletion has run. An
/// adapter can therefore read every participant and restore its covered evolved
/// fields on `contentReferenceID`; the ordinary entity carry then transfers that
/// complete content to `winnerID` when the two identities differ.
struct PayloadEvolutionCollisionContext: Sendable {
  let entityType: EntityKind
  let winnerID: String
  let contentReferenceID: String
  let participants: [(id: String, version: String)]
}

/// Executable coverage for additive fields on one cross-id collision aggregate.
///
/// A field name in `coveredFields` is not a waiver: `preserveFields` runs inside
/// the aggregate savepoint before loser deletion and must implement that
/// entity's deterministic cross-id preservation rule. Release contract tests
/// keep this registry aligned with `field_evolution`; every registration also
/// requires an entity-level opposite-arrival-order probe.
struct PayloadEvolutionCollisionAdapter: Sendable {
  let entityType: EntityKind
  let coveredFields: Set<String>
  let preserveFields:
    @Sendable (_ db: Database, _ context: PayloadEvolutionCollisionContext) throws -> Void
}

enum PayloadEvolutionCollisionAdapterRegistry {
  /// Version 1 has no field introductions, so no adapter is currently needed.
  /// A future registration must ship with its manifest entry and executable
  /// cross-id collision tests in the same change.
  static let registered: [PayloadEvolutionCollisionAdapter] = []

  /// Resolve complete, non-overlapping adapter coverage before the merge mutates
  /// any row. Missing or ambiguous coverage holds the envelope intact rather
  /// than silently materializing a legacy insert default over preserved content.
  static func adaptersOrDefer(
    entityType: EntityKind, entityID: String,
    introductions: [SyncPayloadFieldIntroduction] = SyncPayloadEvolution.fieldIntroductions,
    adapters: [PayloadEvolutionCollisionAdapter] = registered
  ) throws -> [PayloadEvolutionCollisionAdapter] {
    let evolvedFields = Set(
      introductions.lazy
        .filter { $0.entityType == entityType }
        .map(\.fieldName))
    guard !evolvedFields.isEmpty else { return [] }

    let applicable = adapters.filter { $0.entityType == entityType }
    var owners: [String: Int] = [:]
    for adapter in applicable {
      for field in adapter.coveredFields where evolvedFields.contains(field) {
        owners[field, default: 0] += 1
      }
    }
    let missing = evolvedFields.filter { owners[$0] == nil }.sorted()
    let ambiguous = evolvedFields.filter { owners[$0, default: 0] > 1 }.sorted()
    guard missing.isEmpty, ambiguous.isEmpty else {
      let detail =
        "cross-id payload evolution adapter coverage is incomplete "
        + "(missing=\(missing), ambiguous=\(ambiguous))"
      throw ApplyError.deferForwardCompat(
        .aggregateInvariantBlocked(
          entityType: entityType, entityId: entityID, invariant: detail))
    }
    return applicable.filter { !$0.coveredFields.isDisjoint(with: evolvedFields) }
  }
}
