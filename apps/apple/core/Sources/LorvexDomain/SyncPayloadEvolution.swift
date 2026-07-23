/// One additive field introduced after an earlier sync payload schema version.
///
/// This is the small runtime projection of
/// `schema/sync_payload/NNN.json:field_evolution`: the apply driver needs only
/// the entity and introduction version to know that an older-schema upsert may
/// have preserved local fields and therefore requires a corrective full-snapshot
/// re-emit. Contract tests pin this table exactly to the checked-in manifest.
public struct SyncPayloadFieldIntroduction: Sendable, Hashable {
  public let entityType: EntityKind
  public let fieldName: String
  public let introducedIn: UInt32

  public init(entityType: EntityKind, fieldName: String, introducedIn: UInt32) {
    self.entityType = entityType
    self.fieldName = fieldName
    self.introducedIn = introducedIn
  }
}

public enum SyncPayloadEvolution {
  /// Entity kinds whose logical identity can collide even when independently
  /// authored rows have different ids. Their merge picks one row's known
  /// content using a whole-row HLC, which cannot prove provenance for a field
  /// absent from an older payload. Additive field evolution for these kinds is
  /// therefore release-blocked until that field has an executable, cross-id
  /// collision adapter in `LorvexSync`. Already-shipped runtimes separately
  /// defer every collision that still has an opaque participant shadow, so a
  /// future adapter is never expected to repair loss caused by an older binary.
  public static let crossIDCollisionEntityTypes: Set<EntityKind> = [
    .habit,
    .habitReminderPolicy,
    .memory,
    .tag,
  ]

  /// Add one entry for every field in the current manifest's `field_evolution`
  /// object. Version 1 introduced no field relative to an older shipped
  /// contract, so the initial table is intentionally empty.
  public static let fieldIntroductions: [SyncPayloadFieldIntroduction] = []

  /// Whether this runtime knows any field on `entityType` that the incoming
  /// payload schema predates. Such an upsert can legitimately preserve a value
  /// absent from the wire payload, so its merged snapshot must be re-emitted at
  /// a fresh HLC for fresh/rebuilt peers to converge.
  public static func hasFieldIntroduced(
    after payloadSchemaVersion: UInt32, for entityType: EntityKind
  ) -> Bool {
    hasFieldIntroduced(
      after: payloadSchemaVersion, for: entityType, in: fieldIntroductions)
  }

  /// Test seam for proving the rolling-version decision before the first v2
  /// field exists. Production always calls the two-argument overload above.
  public static func hasFieldIntroduced(
    after payloadSchemaVersion: UInt32, for entityType: EntityKind,
    in introductions: [SyncPayloadFieldIntroduction]
  ) -> Bool {
    introductions.contains {
      $0.entityType == entityType && $0.introducedIn > payloadSchemaVersion
    }
  }
}
