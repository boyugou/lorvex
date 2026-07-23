import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexCloudSync

extension AppStore {
  var lastSpotlightIndexedTaskCount: Int {
    get { syncReportsStorage.lastSpotlightIndexedTaskCount }
    set { syncReportsStorage.lastSpotlightIndexedTaskCount = newValue }
  }

  var lastSpotlightIndexedCalendarEventCount: Int {
    get { syncReportsStorage.lastSpotlightIndexedCalendarEventCount }
    set { syncReportsStorage.lastSpotlightIndexedCalendarEventCount = newValue }
  }

  var lastSpotlightTaskIndexErrorMessage: String? {
    get { syncReportsStorage.lastSpotlightTaskIndexErrorMessage }
    set { syncReportsStorage.lastSpotlightTaskIndexErrorMessage = newValue }
  }

  var lastSpotlightContentIndexErrorMessage: String? {
    get { syncReportsStorage.lastSpotlightContentIndexErrorMessage }
    set { syncReportsStorage.lastSpotlightContentIndexErrorMessage = newValue }
  }

  var lastScheduledReminderCount: Int {
    get { syncReportsStorage.lastScheduledReminderCount }
    set { syncReportsStorage.lastScheduledReminderCount = newValue }
  }

  var lastHabitReminderScheduleReport: TaskReminderScheduleReport {
    get { syncReportsStorage.lastHabitReminderScheduleReport }
    set { syncReportsStorage.lastHabitReminderScheduleReport = newValue }
  }

  var lastTaskReminderScheduleReport: TaskReminderScheduleReport {
    get { syncReportsStorage.lastTaskReminderScheduleReport }
    set { syncReportsStorage.lastTaskReminderScheduleReport = newValue }
  }

  var lastPublishedWidgetSnapshot: WidgetSnapshot? {
    get { syncReportsStorage.lastPublishedWidgetSnapshot }
    set { syncReportsStorage.lastPublishedWidgetSnapshot = newValue }
  }

  var lastCloudSyncSubscriptionErrorMessage: String? {
    get { syncReportsStorage.lastCloudSyncSubscriptionErrorMessage }
    set { syncReportsStorage.lastCloudSyncSubscriptionErrorMessage = newValue }
  }

  var lastCloudSyncCycleReport: CloudSyncCycleReport? {
    get { syncReportsStorage.lastCloudSyncCycleReport }
    set { syncReportsStorage.lastCloudSyncCycleReport = newValue }
  }

  var lastCloudSyncRemoteChangeErrorMessage: String? {
    get { syncReportsStorage.lastCloudSyncRemoteChangeErrorMessage }
    set { syncReportsStorage.lastCloudSyncRemoteChangeErrorMessage = newValue }
  }

  var lastCloudSyncRemoteChangeSucceededAt: Date? {
    get { syncReportsStorage.lastCloudSyncRemoteChangeSucceededAt }
    set { syncReportsStorage.lastCloudSyncRemoteChangeSucceededAt = newValue }
  }

  var cloudSyncPacing: CloudSyncPacing {
    get { syncReportsStorage.cloudSyncPacing }
    set { syncReportsStorage.cloudSyncPacing = newValue }
  }

  var cloudKitAccountAvailability: CloudKitAccountAvailability {
    get { syncReportsStorage.cloudKitAccountAvailability }
    set { syncReportsStorage.cloudKitAccountAvailability = newValue }
  }

  var cloudSyncPauseReason: CloudSyncPauseReason? {
    get { syncReportsStorage.cloudSyncPauseReason }
    set { syncReportsStorage.cloudSyncPauseReason = newValue }
  }

  var lastImportedCalendarEventCount: Int {
    get { syncReportsStorage.lastImportedCalendarEventCount }
    set { syncReportsStorage.lastImportedCalendarEventCount = newValue }
  }

  var lastCalendarExportReport: CalendarIntegrationReport {
    get { syncReportsStorage.lastCalendarExportReport }
    set { syncReportsStorage.lastCalendarExportReport = newValue }
  }

  var lastCalendarImportReport: CalendarIntegrationReport {
    get { syncReportsStorage.lastCalendarImportReport }
    set { syncReportsStorage.lastCalendarImportReport = newValue }
  }
}
