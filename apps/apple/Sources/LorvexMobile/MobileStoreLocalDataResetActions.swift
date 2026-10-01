import Foundation
import LorvexCore

extension MobileStore {
  /// Hermetic override for the destructive reset lifecycle. Production leaves
  /// this nil so the reset resolves the real managed store; tests bind a
  /// temporary database URL so they can drive the irreversible branch without
  /// erasing the developer's own App-Group store.
  struct LocalDataResetDependencies: Sendable {
    let databaseURL: URL
  }

  @TaskLocal static var localDataResetDependencies: LocalDataResetDependencies?

  /// The managed database file this reset erases: the injected test URL when one
  /// is bound, else the App-Group path the running core actually opened.
  ///
  /// `nil` when the managed path fails closed — a sandboxed build whose App
  /// Group container is unresolvable. The reset treats that as "cannot safely
  /// erase" and aborts with the storage untouched rather than deleting a
  /// per-process fallback file the core never used.
  static func localDataResetDatabaseURL() -> URL? {
    if let override = localDataResetDependencies { return override.databaseURL }
    guard let path = try? SwiftLorvexCoreService.managedDatabasePath() else { return nil }
    return URL(fileURLWithPath: path)
  }

  /// Erase all Lorvex data and settings on this device and return it to a
  /// first-launch state.
  ///
  /// Deliberately local-only, mirroring the macOS reset: records already synced
  /// stay in the CloudKit zone and download again when the user re-enables sync
  /// (the confirmation says so). ``deleteCloudDataEverywhere()`` is the separate,
  /// explicit action that removes the iCloud copy. It never touches EventKit —
  /// the erased `provider_calendar_events` rows are a disposable device-local
  /// mirror whose real events live in the system Calendar and are re-ingested on
  /// demand, and Lorvex's write-back calendar is left in place.
  ///
  /// Returns `nil` on success, or a localized user-facing message when nothing
  /// was erased.
  public func performLocalDataReset() async -> String? {
    guard !isSettingCloudSyncMode, !isDataImportRunning, !isCloudDataDeletionRunning,
      !isLocalDataResetRunning
    else {
      return String(
        localized: "settings.reset_device.error.busy",
        defaultValue: "Lorvex is busy. Try again in a moment.", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    // A nil managed path means the App Group container could not be resolved, so
    // there is no store this process actually opened. Abort with the data intact
    // rather than deleting a per-process fallback file the core never used.
    guard let url = Self.localDataResetDatabaseURL() else {
      return String(
        localized: "settings.reset_device.error.failed",
        defaultValue: "Couldn’t finish erasing this device’s data. Reopen Lorvex and try again.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    isLocalDataResetRunning = true
    defer { isLocalDataResetRunning = false }

    // Stop sync before touching the files: turning the runtime mode off keeps
    // the reset's own refresh from starting a pass, and stopping the
    // controller cancels the engine's operations, so no fetched batch lands in
    // the fresh database and repopulates what the user just erased.
    let previousCloudSyncMode = cloudSyncMode
    cloudSyncMode = .off
    await cloudSyncController?.stop()

    // Clear the OS-owned derived surfaces while the canonical rows are still
    // readable. The ordinary scheduling fan-out preserves prior content on
    // failure; an erase has the opposite contract.
    await clearNotificationSurfacesForLocalDataReset()

    let coreToClose = core
    let cutover: @Sendable () async throws -> Void = {
      // The store reopens lazily on the next read/write, so the same service
      // instance continues against the recreated file — no core replacement.
      // Cached per-surface services (intents, notification actions) hold their
      // own connections to the file being deleted, hence the eviction.
      //
      // The reopen resolves the managed path rather than restoring whatever the
      // service opened before, so closing an IN-MEMORY core here turns it into a
      // managed-store core on its next read. That only matters to tests and
      // previews, which is why this action's tests assert on settings and
      // runtime state instead of reading rows back afterwards.
      (coreToClose as? SwiftLorvexCoreService)?.closeStoreForCutover()
      LorvexCoreRuntimeFactory.invalidateCachedServices()
      _ = try SwiftLorvexCoreService.resetManagedStorage(at: url)
    }

    do {
      try await cutover()
    } catch {
      // The erase did not report a completed wipe. Restore the runtime sync mode
      // and rebuild from whatever canonical database remains before reporting.
      cloudSyncMode = previousCloudSyncMode
      _ = await refresh()
      return String(
        localized: "settings.reset_device.error.failed",
        defaultValue: "Couldn’t finish erasing this device’s data. Reopen Lorvex and try again.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }

    // The erased database took the engine state with it; drop the cached
    // record versions too, so turning sync back on fetches the zone afresh.
    await cloudSyncController?.forgetCachedRecordState()
    MobileSetupPreferences(defaults: defaults).resetToDefaults()
    clearSelectionsForLocalDataReset()
    _ = await refresh()
    return nil
  }

  /// Drop every scheduled reminder and snooze this device owns. Runs before the
  /// wipe, while the rows the schedulers key off are still readable.
  private func clearNotificationSurfacesForLocalDataReset() async {
    _ = await taskReminderScheduler.scheduleReminders([])
    await taskReminderScheduler.cancelSnoozes(keepingActiveTaskIDs: [])
    lastHabitReminderScheduleReport =
      await habitReminderScheduler.replaceScheduledHabitReminders(for: [])
  }

  /// Forget what the UI had open. The refresh that follows reloads every surface
  /// from the empty store, but a retained id would otherwise keep a detail view
  /// pointed at a row that no longer exists.
  private func clearSelectionsForLocalDataReset() {
    selectedTaskID = nil
    selectedHabitID = nil
    selectedMemoryKey = nil
    memoryEditingKey = nil
  }
}
