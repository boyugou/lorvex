/// Version constants for the Lorvex system — the single source of truth for
/// sync protocol, schema management, and UI display.
public enum LorvexVersion {
  /// Application version string.
  public static let appVersion = "1.0.0"
  /// Payload schema version for sync envelopes.
  public static let payloadSchemaVersion: UInt32 = 4

  /// Version 4 introduces two independent preference record identities.
  /// Every existing record still has its exact v3 wire shape. Keeping its
  /// ordinary writes on v3 lets older clients continue merging them normally.
  public static func compatiblePayloadVersion(
    for kind: EntityKind, id: String, version: UInt32 = payloadSchemaVersion
  ) -> UInt32 {
    if version == 4,
      !(kind == .preference
        && (id == PreferenceKeys.prefMorningRoutine || id == PreferenceKeys.prefEveningRoutine))
    {
      return 3
    }
    return version
  }
}
