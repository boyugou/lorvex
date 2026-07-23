import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexCloudSync

/// Holds runtime state for Apple-surface sync and publishing reports:
/// Spotlight indexing counts, widget snapshot, cloud-sync envelope and report,
/// and calendar import/export counts and reports.
struct AppStoreSyncReportsStorage {
  var lastSpotlightIndexedTaskCount = 0
  var lastSpotlightIndexedCalendarEventCount = 0
  var lastSpotlightTaskIndexErrorMessage: String?
  var lastSpotlightContentIndexErrorMessage: String?
  var lastScheduledReminderCount = 0
  var lastTaskReminderScheduleReport: TaskReminderScheduleReport = .disabled
  var lastHabitReminderScheduleReport: TaskReminderScheduleReport = .disabled
  var lastPublishedWidgetSnapshot: WidgetSnapshot?
  var lastCloudSyncSubscriptionErrorMessage: String?
  /// The most recent sync cycle's outcome (outbound push counts + inbound apply
  /// report), or nil before the first cycle runs.
  var lastCloudSyncCycleReport: CloudSyncCycleReport?
  var lastCloudSyncRemoteChangeErrorMessage: String?
  /// Timestamp of the last successful sync cycle. Set when
  /// `refreshCloudSyncRemoteChanges` completes without throwing.
  var lastCloudSyncRemoteChangeSucceededAt: Date?
  /// Failure-aware pacing for the invisible sync cycle: consecutive-failure
  /// count, last attempt time, and circuit-breaker state. Gates whether a
  /// trigger actually runs a cycle (see `AppStore.runCloudSyncCycle`).
  var cloudSyncPacing = CloudSyncPacing()
  /// Most recent iCloud account availability, refreshed when the Cloud Sync
  /// settings tab appears (see `AppStore.refreshCloudKitAccountAvailability`).
  var cloudKitAccountAvailability: CloudKitAccountAvailability = .couldNotDetermine
  /// Non-nil when CloudSync is durably paused (iCloud account switch, mandatory
  /// backfill failure, or a Lorvex iCloud-data deletion). Surfaced so the
  /// Cloud Sync settings tab can show a "sync paused" notice and offer the
  /// re-upload/resume action; refreshed alongside the account availability and
  /// after each sync cycle.
  var cloudSyncPauseReason: CloudSyncPauseReason?
  var lastImportedCalendarEventCount = 0
  var lastCalendarExportReport: CalendarIntegrationReport = .notStarted
  var lastCalendarImportReport: CalendarIntegrationReport = .notStarted

  mutating func reset() {
    lastSpotlightIndexedTaskCount = 0
    lastSpotlightIndexedCalendarEventCount = 0
    lastSpotlightTaskIndexErrorMessage = nil
    lastSpotlightContentIndexErrorMessage = nil
    lastScheduledReminderCount = 0
    lastTaskReminderScheduleReport = .disabled
    lastHabitReminderScheduleReport = .disabled
    lastPublishedWidgetSnapshot = nil
    lastCloudSyncSubscriptionErrorMessage = nil
    lastCloudSyncCycleReport = nil
    lastCloudSyncRemoteChangeErrorMessage = nil
    lastCloudSyncRemoteChangeSucceededAt = nil
    cloudSyncPacing = CloudSyncPacing()
    cloudKitAccountAvailability = .couldNotDetermine
    cloudSyncPauseReason = nil
    lastImportedCalendarEventCount = 0
    lastCalendarExportReport = .notStarted
    lastCalendarImportReport = .notStarted
  }
}
