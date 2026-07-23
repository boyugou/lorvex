import LorvexCore
import LorvexSync

extension CloudSyncCycleReport {
  public mutating func accumulate(_ other: CloudSyncCycleReport) {
    pushedRecordCount += other.pushedRecordCount
    failedPushCount += other.failedPushCount
    fetchedRecordCount += other.fetchedRecordCount
    moreInboundComing = other.moreInboundComing
    moreOutboundComing = other.moreOutboundComing
    inbound.accumulate(other.inbound)
    // This is a snapshot of durable work after the latest page, not a count to
    // accumulate: a later page may have re-armed and consumed an earlier due row.
    nextDeferredRetryAt = other.nextDeferredRetryAt
  }
}

extension CloudSyncEngineCoordinator {
  func emptyReport() -> CloudSyncCycleReport {
    CloudSyncCycleReport(
      pushedRecordCount: 0, failedPushCount: 0,
      fetchedRecordCount: 0, moreInboundComing: false,
      inbound: InboundApplyReport())
  }
}
