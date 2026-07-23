import Foundation
import LorvexCore
import LorvexDomain

extension AppStore {

  /// Drive the calendar permission grant through the app's own EventKit store
  /// (not a throwaway one) so the grant latches, the store is reset to see the
  /// newly-authorized calendars, and the current window re-ingests — the
  /// calendar and the calendar settings populate immediately, no app relaunch.
  /// Used by the Permissions "Allow" button.
  @discardableResult
  func requestCalendarAccessFromSettings() async -> Bool {
    guard let eventKitCoordinator else { return false }
    do {
      let granted = try await eventKitCoordinator.requestAccess()
      if granted {
        try? await refreshCalendarTimeline(requestCalendarAccess: false)
      }
      return granted
    } catch {
      lastCalendarImportReport = .failed(operation: "eventkit-permission", error: error)
      return false
    }
  }

  /// Apply the user's EventKit calendar settings — the enable/disable toggle, the
  /// calendar include/exclude filters, and an explicit re-ingest ("Ingest Now").
  /// None of these expresses a detail-tier choice, so this path never writes
  /// `calendar_ai_access_mode`; a plain enable/disable/filter/refresh cannot
  /// silently raise or lower the user's persisted device-local privacy tier.
  ///
  /// It then reads the effective stored tier to decide provider-scope
  /// availability (an `off` tier keeps the mirror disabled even when the toggle
  /// is on) and re-ingests the current window so the mirror + week grid reflect
  /// the live tier. `enabled == false` clears the local mirror. Failures surface
  /// through the import report, never `errorMessage`.
  func applyEventKitSettings(enabled: Bool) async {
    // The master integration toggle independently owns outbound macOS
    // write-back. Update its gate even if reconciling the inbound provider
    // scope fails below; a disabled master switch must never leave write-back
    // enabled just because a local database operation threw.
    eventKitIntegrationEnabled = enabled
    let accessMode = await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core)
    let effectiveEnabled = enabled && accessMode.includesProvider
    if let provider = core as? any EventKitProviderServicing {
      do {
        try provider.setEventKitScopeEnabled(effectiveEnabled)
      } catch {
        // A failed scope write leaves the persisted EventKit state out of sync
        // with the effective tier; report it rather than swallow, and skip the
        // re-ingest that would run against the stale scope.
        lastCalendarImportReport = .failed(operation: "eventkit-scope", error: error)
        return
      }
    }
    do {
      try await refreshCalendarTimeline(requestCalendarAccess: true)
    } catch {
      lastCalendarImportReport = .failed(operation: "eventkit-refresh", error: error)
    }
  }

  /// Read the effective device-local EventKit detail tier for Settings. Missing
  /// or unreadable state fails down to the domain default (`busy_only`).
  func calendarAccessModeFromSettings() async -> CalendarAiAccessMode {
    await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core)
  }

  /// Persist an explicit Settings choice, then immediately reconcile the
  /// provider scope and current mirror window at that tier. The core owns the
  /// atomic downgrade purge; Settings never keeps a second UserDefaults copy.
  @discardableResult
  func setCalendarAccessModeFromSettings(
    _ mode: CalendarAiAccessMode,
    enabled: Bool
  ) async -> Bool {
    do {
      _ = try await core.setPreference(
        key: PreferenceKeys.devCalendarAiAccessMode,
        value: mode.asString)
    } catch {
      lastCalendarImportReport = .failed(operation: "eventkit-access-mode", error: error)
      return false
    }
    await applyEventKitSettings(enabled: enabled)
    return true
  }
}
