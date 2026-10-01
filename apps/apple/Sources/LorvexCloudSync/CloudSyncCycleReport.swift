import Foundation
import LorvexCore

/// What one sync pass did: records sent and fetched, and the local apply outcome.
public struct CloudSyncCycleReport: Equatable, Sendable {
  public var pushedRecordCount: Int
  public var failedPushCount: Int
  public var fetchedRecordCount: Int
  public var inbound: InboundApplyReport
  /// CloudKit rejected a save because the user's iCloud storage is full. The
  /// affected rows stay queued and go out once space is available.
  public var iCloudStorageFull: Bool

  public init(
    pushedRecordCount: Int, failedPushCount: Int, fetchedRecordCount: Int,
    inbound: InboundApplyReport, iCloudStorageFull: Bool = false
  ) {
    self.pushedRecordCount = pushedRecordCount
    self.failedPushCount = failedPushCount
    self.fetchedRecordCount = fetchedRecordCount
    self.inbound = inbound
    self.iCloudStorageFull = iCloudStorageFull
  }

  /// A pass that did nothing.
  public static let empty = CloudSyncCycleReport(
    pushedRecordCount: 0, failedPushCount: 0, fetchedRecordCount: 0,
    inbound: InboundApplyReport())

  /// Folds a later pass into this one: counts add up, and a full iCloud
  /// storage reported by either pass stays reported.
  public mutating func accumulate(_ other: CloudSyncCycleReport) {
    pushedRecordCount += other.pushedRecordCount
    failedPushCount += other.failedPushCount
    fetchedRecordCount += other.fetchedRecordCount
    inbound.accumulate(other.inbound)
    iCloudStorageFull = iCloudStorageFull || other.iCloudStorageFull
  }
}
