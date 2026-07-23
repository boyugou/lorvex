/// Version constants for the Lorvex system — the single source of truth for
/// sync protocol, schema management, and UI display.
public enum LorvexVersion {
  /// Application version string.
  public static let appVersion = "1.0.0"
  /// Payload schema version for sync envelopes.
  public static let payloadSchemaVersion: UInt32 = 1
}
