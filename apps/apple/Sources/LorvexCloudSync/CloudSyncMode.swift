/// The user-facing Cloud Sync mode.
///
/// - `off`: Cloud Sync is disabled. No records are pushed or fetched, no
///   CloudKit connections are opened.
/// - `live`: Full two-way sync — the `CloudSyncController` uploads the outbox
///   to CloudKit and applies inbound changes, on launch, after local writes,
///   and when a push arrives.
///
/// The env var `LORVEX_CLOUD_SYNC` overrides this setting when set:
/// "live" maps to `.live`, any other value to `.off`. When the env var is
/// absent the persisted setting takes effect. The default when neither is set
/// is `.off`.
public enum CloudSyncMode: String, CaseIterable, Identifiable, Sendable {
  case off
  case live

  public var id: String { rawValue }
}
