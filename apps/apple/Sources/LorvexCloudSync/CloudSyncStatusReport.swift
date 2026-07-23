import Foundation

/// An aggregated view of CloudKit sync status, derived from push reports,
/// pull reports, account availability, and the durable pause reason.
///
/// This is a computed snapshot — it does not store independent state. The
/// AppStore produces it from `syncReportsStorage` plus the current account
/// availability. Suitable for display in Settings and for test assertions.
public struct CloudSyncStatusReport: Equatable, Sendable {
  public var mode: CloudSyncMode
  public var accountAvailability: CloudKitAccountAvailability
  /// The durable reason sync is paused (account changed, zone deleted, backfill
  /// failed), or nil when not paused. A standing pause means sync has stopped
  /// until the user acts, so it gates ``isOperational`` even when the mode is
  /// `.live` and the account is available.
  public var pauseReason: CloudSyncPauseReason?
  /// Timestamp of the last successful push to CloudKit, nil if no push has succeeded.
  public var lastPushAt: Date?
  /// Error message from the most recent push attempt, nil if the last push succeeded.
  public var lastPushError: String?
  /// Timestamp of the last successful pull from CloudKit, nil if no pull has succeeded.
  public var lastPullAt: Date?
  /// Error message from the most recent pull attempt, nil if the last pull succeeded.
  public var lastPullError: String?
  /// Pending local-change count from the Swift core's sync status snapshot.
  public var pendingCount: Int

  public init(
    mode: CloudSyncMode,
    accountAvailability: CloudKitAccountAvailability,
    pauseReason: CloudSyncPauseReason?,
    lastPushAt: Date?,
    lastPushError: String?,
    lastPullAt: Date?,
    lastPullError: String?,
    pendingCount: Int
  ) {
    self.mode = mode
    self.accountAvailability = accountAvailability
    self.pauseReason = pauseReason
    self.lastPushAt = lastPushAt
    self.lastPushError = lastPushError
    self.lastPullAt = lastPullAt
    self.lastPullError = lastPullError
    self.pendingCount = pendingCount
  }

  /// Sync is live, the account is reachable, and no durable pause is standing.
  /// A pause (account changed, zone deleted, backfill failed) stops sync until
  /// the user acts, so it reads as NOT operational even under a `.live` mode —
  /// the Settings icon must not show green over a "Sync Paused" notice.
  public var isOperational: Bool {
    mode == .live && accountAvailability == .available && pauseReason == nil
  }
}
