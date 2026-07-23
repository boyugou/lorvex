import Foundation
import LorvexCore
import LorvexWidgetKitSupport

private enum FactoryResetDerivedSurfaceError: Error {
  case reminderCleanupFailed(String)
  case widgetDestinationMismatch
}

extension AppStore {
  /// Hermetic override for the destructive reset lifecycle. Production leaves
  /// this nil; tests bind a temporary managed path and replacement core so they
  /// can drive the irreversible post-reset branch without touching the user's
  /// real App-Group store.
  struct FactoryResetDependencies: @unchecked Sendable {
    let databaseURL: URL?
    let makeReplacementCore: @Sendable () -> any LorvexCoreServicing
  }

  @TaskLocal static var factoryResetDependencies: FactoryResetDependencies?

  /// The Lorvex-managed local-storage DB file the core actually opens — the App
  /// Group container path on signed/sandboxed builds, resolved through the same
  /// `DbLocator` precedence the running core uses. Deliberately NOT a hardcoded
  /// Application Support path: under the App Sandbox that resolves to a private
  /// container the core never writes to, so deleting it would leave the real
  /// App-Group database (and all user data) intact.
  ///
  /// `nil` when the managed path fails closed — a sandboxed build whose App Group
  /// container is unresolvable. `performFactoryReset` treats that as "cannot
  /// safely erase" and aborts with the storage untouched, rather than deleting a
  /// per-process fallback file the core never used.
  static func defaultDatabaseURL() -> URL? {
    if let override = factoryResetDependencies { return override.databaseURL }
    guard let path = try? SwiftLorvexCoreService.managedDatabasePath() else { return nil }
    return URL(fileURLWithPath: path)
  }

  /// Erase all Lorvex data and settings on this Mac and return to a first-launch
  /// state.
  ///
  /// Resets every preference (`setupCompleted` back to false), deletes the
  /// Lorvex-managed local data so the schema is recreated empty, then rebuilds the
  /// core.
  ///
  /// Scope — this only erases Lorvex's own local store, on this Mac. It is
  /// deliberately local-only: records already synced to iCloud stay in the
  /// CloudKit zone and re-download when sync is re-enabled (the reset dialog
  /// says so; `deleteCloudDataEverywhere` is the separate, explicit action
  /// that removes the iCloud copy). It never touches the
  /// system calendar: the deleted `provider_calendar_events` rows are a
  /// disposable, device-local mirror of the user's external (EventKit) calendars
  /// — the real events live in macOS Calendar and are re-ingested on demand, so
  /// wiping the mirror cannot delete anything from the user's Google/iCloud/other
  /// calendars. The dedicated Lorvex write-back calendar (and any blocks Lorvex
  /// wrote into it) is likewise left in place; no EventKit delete is issued.
  func performFactoryReset(settings: AppSettingsStore) async {
    guard !isDataImportRunning, !isLocalFactoryResetRunning,
      !isCloudDataDeletionRunning, !isCloudDeletionMaintenanceRunning
    else { return }
    isLocalFactoryResetRunning = true
    defer { isLocalFactoryResetRunning = false }
    guard !settings.usesEnvironmentDatabasePath else {
      errorMessage = String(
        localized: "settings.reset.environment_database_error",
        defaultValue:
          "Lorvex is using a database path from the launch environment. Remove that environment setting and restart Lorvex before resetting local data.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
      return
    }
    // No pre-reset refresh may remain in flight while its detached Spotlight,
    // notification, badge, or widget work is about to be cleared. New ordinary
    // refresh triggers observe `isLocalFactoryResetRunning` and no-op until the
    // replacement core is installed; this await drains a leader that entered
    // before the flag was raised.
    if isRefreshing {
      await refreshAndWaitForLatest()
    }
    // After resolving the canonical path below, quiesce CloudKit sync at the
    // app level BEFORE closing/wiping the store, so
    // the post-reset `replaceCore → refresh → publishAppleSyncSurfaces →
    // runCloudSyncCycle` no-ops instead of running a cycle against the fresh,
    // empty database. `runCloudSyncCycle` guards on the RUNTIME `cloudSyncMode`;
    // `settings.resetToDefaults()` below flips only the PERSISTED mode, leaving
    // the runtime value `.live` for the reset's own refresh. That refresh's cycle
    // would find a database with no traversal state and start a nil-token baseline
    // against the still-existing CloudKit generation — repopulating the database
    // the user just erased. Turning the
    // runtime mode off (and resetting pacing) mirrors `deleteCloudDataEverywhere`;
    // no `userDeletedZone` pause, because a local reset leaves the cloud copy
    // intact and re-downloads it when the user re-enables sync.
    // Delete before mutating settings: a failed erase must abort with the
    // storage selection untouched, never leave settings reset but the data
    // intact. The managed path is independent of the storage preference, so
    // resolving it first is safe. A nil path means the managed store's location
    // could not be resolved at all (a sandboxed build whose App Group container
    // is unavailable): there is nothing safe to erase, so abort rather than
    // reset settings against a store the core never opened.
    guard let url = Self.defaultDatabaseURL() else {
      errorMessage = String(
        localized: "settings.reset.delete_failed",
        defaultValue:
          "Couldn’t finish erasing local data. Restart Lorvex and try again.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
      return
    }
    // Resolve the canonical path before changing runtime state. A failed App
    // Group lookup must leave live sync exactly as it was; otherwise the guard
    // above would return with persisted settings still live but this process
    // silently stuck off.
    let previousCloudSyncMode = cloudSyncMode
    cloudSyncMode = .off
    cloudSyncPacing.reset()
    let widgetResetTarget = widgetSnapshotPublisher.factoryResetTarget
    // Quiesce CloudSync before touching the files. Setting the runtime mode off
    // prevents new host-triggered cycles, while the coordinator gate waits for
    // any already-detached cycle/account action to reach a terminal boundary and
    // keeps it out through close + generation bump + deletion. The storage lock
    // protects individual DB calls, but without this wider boundary an old cycle
    // could finish one transaction, let reset replace the file, then continue its
    // next phase against the fresh database and silently repopulate the reset.
    let coreToClose = core
    let resetStorage: @Sendable () throws -> Int = {
      // The main service and every cached per-surface service (in-process
      // intents, Spotlight, notification actions) hold open GRDB connections to
      // the managed file. Both closes are idempotent and reopen lazily, so a
      // failed erase leaves the original file consistent and reopenable.
      (coreToClose as? SwiftLorvexCoreService)?.closeStoreForCutover()
      LorvexCoreRuntimeFactory.invalidateCachedServices()
      return try SwiftLorvexCoreService.resetManagedStorage(at: url)
    }
    // This is empty-cache metadata only. A fresh core refresh immediately
    // replaces it with the product-timezone day captured inside SQLite. Using a
    // stable minimum avoids reintroducing the device-timezone/midnight race the
    // production widget source deliberately eliminates.
    let resetBarrierLogicalDay = "1970-01-01"
    let cutover: @Sendable () async throws -> WidgetSnapshotFactoryResetOutcome? = {
      // Clear every OS-owned derived surface directly. The ordinary refresh
      // path deliberately preserves old content on read failure; factory reset
      // has the opposite contract and must not rely on that best-effort fan-out.
      try await self.clearDerivedSurfacesForFactoryReset()
      if let widgetResetTarget {
        guard widgetResetTarget.managedDatabasePath == url.path else {
          throw FactoryResetDerivedSurfaceError.widgetDestinationMismatch
        }
        return try await widgetResetTarget.replaceWithEmptyBarrier(
          logicalDay: resetBarrierLogicalDay,
          resetStorage: resetStorage)
      } else {
        _ = try resetStorage()
        return nil
      }
    }
    let widgetResetOutcome: WidgetSnapshotFactoryResetOutcome?
    do {
      if let coordinator = cloudSyncCoordinator ?? cloudDataMaintenanceCoordinator {
        widgetResetOutcome = try await coordinator.withQuiescedCloudSync(cutover)
      } else {
        widgetResetOutcome = try await cutover()
      }
    } catch {
      // Every throw from `cutover` means the storage reset did not report a
      // completed canonical wipe. Derived OS surfaces may already have been
      // cleared (and a low-level cutover may have advanced its marker before an
      // I/O failure), so restore the runtime sync mode and best-effort rebuild
      // from whatever canonical database remains before reporting the failure.
      cloudSyncMode = previousCloudSyncMode
      cloudSyncPacing.reset()
      await refreshAndWaitForLatest()
      errorMessage = String(
        localized: "settings.reset.delete_failed",
        defaultValue:
          "Couldn’t finish erasing local data. Restart Lorvex and try again.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
      return
    }
    settings.resetToDefaults()
    let replacementCore =
      Self.factoryResetDependencies?.makeReplacementCore() ?? AppCoreFactory.make()
    await replaceCore(replacementCore, refreshAfterReplacement: false)
    await refreshAndWaitForLatest()
    if widgetResetOutcome?.publicationSucceeded == false,
      lastPublishedWidgetSnapshot == nil
    {
      // Canonical storage and settings are already reset. This is deliberately
      // a post-reset derived-cache warning, not the pre-cutover "nothing was
      // removed" error used above.
      errorMessage = String(
        localized: "settings.reset.widget_cache_warning",
        defaultValue:
          "Local data was erased, but Lorvex couldn’t clear the widget cache. Restart Lorvex and erase local data again.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }

  /// Deterministically remove user-derived data from OS-owned local surfaces.
  /// This never touches EventKit: system-calendar events and Lorvex's dedicated
  /// write-back calendar remain owned by Calendar, exactly as the reset dialog
  /// promises.
  func clearDerivedSurfacesForFactoryReset() async throws {
    try await taskSearchIndexer.replaceIndexedTasks([])
    try await contentSearchIndexer.replaceIndexedLists([])
    try await contentSearchIndexer.replaceIndexedHabits([])
    try await contentSearchIndexer.replaceIndexedDailyReview(nil)
    try await contentSearchIndexer.replaceIndexedCalendarEvents([])

    let taskReport = await taskReminderScheduler.scheduleReminders([])
    guard taskReport.status == .scheduled || taskReport.status == .disabled else {
      throw FactoryResetDerivedSurfaceError.reminderCleanupFailed("task reminders")
    }
    await taskReminderScheduler.cancelSnoozes(keepingActiveTaskIDs: [])
    let habitReport = await habitReminderScheduler.replaceScheduledHabitReminders(for: [])
    guard habitReport.status == .scheduled || habitReport.status == .disabled else {
      throw FactoryResetDerivedSurfaceError.reminderCleanupFailed("habit reminders")
    }
    // Replacing pending requests cannot retract notifications that already
    // fired. Those notifications can retain task titles, opted-in task notes,
    // and habit names in Notification Center after the database is erased, so
    // factory reset explicitly clears the app's delivered notification history.
    await clearDeliveredNotificationsForFactoryReset()

    menuBarAttentionCount = 0
    await setBadge(0)
    lastSpotlightIndexedTaskCount = 0
    lastSpotlightIndexedCalendarEventCount = 0
    lastScheduledReminderCount = 0
    lastTaskReminderScheduleReport = taskReport
    lastHabitReminderScheduleReport = habitReport
    lastPublishedWidgetSnapshot = nil
  }
}
