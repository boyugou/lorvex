public struct SyncStatusSnapshot: Equatable, Sendable {
  public var backend: String
  public var pendingCount: Int
  public var retryingCount: Int
  public var failedCount: Int
  /// `created_at` of the oldest still-pending outbox row (nil when none pending).
  public var oldestPendingAt: String?
  /// `created_at` of the newest still-pending outbox row (nil when none pending).
  public var newestPendingAt: String?
  public var lastSyncedAt: String?
  public var lastError: String?
  public var deviceID: String?
  /// True when the core has recorded the `reseed_required` sync checkpoint:
  /// horizon GC hard-deleted un-applied inbound data, so this device is more
  /// than the full-resync horizon behind and can only recover the lost records
  /// by reseeding from a full resync. The core clears the marker on its own
  /// after a successful full-resync backfill.
  public var reseedRequired: Bool

  public init(
    backend: String,
    pendingCount: Int,
    retryingCount: Int,
    failedCount: Int,
    oldestPendingAt: String? = nil,
    newestPendingAt: String? = nil,
    lastSyncedAt: String?,
    lastError: String?,
    deviceID: String?,
    reseedRequired: Bool = false
  ) {
    self.backend = backend
    self.pendingCount = pendingCount
    self.retryingCount = retryingCount
    self.failedCount = failedCount
    self.oldestPendingAt = oldestPendingAt
    self.newestPendingAt = newestPendingAt
    self.lastSyncedAt = lastSyncedAt
    self.lastError = lastError
    self.deviceID = deviceID
    self.reseedRequired = reseedRequired
  }
}
