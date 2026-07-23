/// The user-facing Cloud Sync mode.
///
/// - `off`: Cloud Sync is disabled. No records are pushed or fetched, no
///   CloudKit connections are opened.
/// - `recordPlan`: Registers the push subscription but runs no sync cycle — the
///   factory intentionally creates no coordinator for this mode, so nothing is
///   pushed, pulled, or applied. A debug dry-run that exercises subscription
///   setup without moving data.
/// - `live`: Full two-way sync — the engine coordinator drains the outbox to
///   CloudKit and applies inbound CloudKit changes through `applyEnvelope`,
///   triggered on launch, after local writes, and on push notification.
///
/// The env var `LORVEX_CLOUDKIT_EXPORT` overrides this setting when set.
/// "record-plan" maps to `.recordPlan`; "live" maps to `.live`.
/// When the env var is absent the persisted `AppSettingsStore.cloudSyncMode`
/// value takes effect. The default when neither is set is `.off`.
public enum CloudSyncMode: String, CaseIterable, Identifiable, Sendable {
  case off
  case recordPlan = "record-plan"
  case live

  public var id: String { rawValue }
}
