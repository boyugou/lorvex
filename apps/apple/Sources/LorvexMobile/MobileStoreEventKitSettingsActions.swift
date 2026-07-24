import Foundation
import LorvexCore
import LorvexDomain

extension MobileStore {
  public var eventKitCalendarFilter: EventKitCalendarFilter {
    EventKitCalendarFilter(
      mode: eventKitCalendarFilterMode,
      selectedCalendarIDs: eventKitIncludedCalendarIDs,
      excludedCalendarIDs: eventKitExcludedCalendarIDs)
  }

  public func loadEventKitCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard let eventKitCoordinator else { return [] }
    do {
      let calendars = try await eventKitCoordinator.availableCalendars(enabled: eventKitEnabled)
      clearEventKitSettingsRecovery()
      return calendars
    } catch {
      if Self.isEventKitReadDenied(error) {
        presentEventKitSettingsRecovery(Self.eventKitAccessDeniedMessage)
      } else {
        eventKitSettingsRecoveryNeeded = false
      }
      throw error
    }
  }

  public func setEventKitEnabledFromSettings(_ enabled: Bool) async {
    guard eventKitEnabled != enabled else { return }
    guard !isSettingEventKitEnabled else { return }
    isSettingEventKitEnabled = true
    defer { isSettingEventKitEnabled = false }
    let prefs = MobileSetupPreferences(defaults: defaults)
    if enabled {
      do {
        let granted = try await eventKitCoordinator?.requestAccess() ?? false
        guard granted else {
          eventKitEnabled = false
          prefs.setEventKitEnabled(false)
          presentEventKitSettingsRecovery(Self.eventKitAccessDeniedMessage)
          await loadRuntimeDiagnostics()
          return
        }
      } catch {
        if Self.isEventKitReadDenied(error) {
          presentEventKitSettingsRecovery(Self.eventKitAccessDeniedMessage)
        } else {
          lastEventKitImportErrorMessage = await userFacingBannerMessage(
            for: error, source: "ios.settings.eventkit_import_failed")
          eventKitSettingsRecoveryNeeded = false
        }
        await loadRuntimeDiagnostics()
        return
      }
    }
    eventKitEnabled = enabled
    prefs.setEventKitEnabled(enabled)
    await applyEventKitSettingsFromSettings(requestAccess: false)
  }

  public func setEventKitCalendarFilterModeFromSettings(_ mode: EventKitCalendarFilterMode) {
    eventKitCalendarFilterMode = mode
    let prefs = MobileSetupPreferences(defaults: defaults)
    prefs.setEventKitCalendarFilterMode(mode)
    switch mode {
    case .allExcept:
      eventKitIncludedCalendarIDs = []
      prefs.setEventKitIncludedCalendarIDs([])
    case .onlySelected:
      eventKitExcludedCalendarIDs = []
      prefs.setEventKitExcludedCalendarIDs([])
    }
  }

  public func setEventKitIncludedCalendarIDsFromSettings(_ ids: Set<String>) {
    eventKitIncludedCalendarIDs = ids
    MobileSetupPreferences(defaults: defaults).setEventKitIncludedCalendarIDs(ids)
  }

  public func setEventKitExcludedCalendarIDsFromSettings(_ ids: Set<String>) {
    eventKitExcludedCalendarIDs = ids
    MobileSetupPreferences(defaults: defaults).setEventKitExcludedCalendarIDs(ids)
  }

  public func applyEventKitSettingsFromSettings(requestAccess: Bool = true) async {
    pendingEventKitSettingsRequestAccess =
      pendingEventKitSettingsRequestAccess || requestAccess
    await eventKitSettingsApplyFlight.run {
      let shouldRequestAccess = pendingEventKitSettingsRequestAccess
      pendingEventKitSettingsRequestAccess = false
      await performEventKitSettingsApply(requestAccess: shouldRequestAccess)
    }
  }

  private func performEventKitSettingsApply(requestAccess: Bool) async {
    isApplyingEventKitSettings = true
    defer { isApplyingEventKitSettings = false }
    do {
      let window = eventKitIngestWindow()
      if calendarTimeline != nil {
        try await refreshCalendarTimelineForSettings(
          fromDay: window.fromDay,
          throughDay: window.throughDay,
          requestAccess: requestAccess)
      } else {
        try await ingestEventKitWindowThrowing(
          fromDay: window.fromDay,
          throughDay: window.throughDay,
          requestAccess: requestAccess)
      }
      clearEventKitSettingsRecovery()
    } catch {
      if Self.isEventKitReadDenied(error) {
        presentEventKitSettingsRecovery(Self.eventKitAccessDeniedMessage)
      } else {
        lastEventKitImportErrorMessage = await userFacingBannerMessage(
          for: error, source: "ios.settings.eventkit_import_failed")
        eventKitSettingsRecoveryNeeded = false
      }
    }
    await loadRuntimeDiagnostics()
  }

  func ingestEventKitWindow(
    fromDay: String,
    throughDay: String,
    requestAccess: Bool = false
  ) async {
    do {
      try await ingestEventKitWindowThrowing(
        fromDay: fromDay,
        throughDay: throughDay,
        requestAccess: requestAccess)
      lastEventKitImportErrorMessage = nil
    } catch {
      lastEventKitImportErrorMessage = await userFacingBannerMessage(
        for: error, source: "ios.settings.eventkit_import_failed")
    }
  }

  func ingestEventKitWindowThrowing(
    fromDay: String,
    throughDay: String,
    requestAccess: Bool
  ) async throws {
    guard let eventKitCoordinator,
      let instantRange = PlannedDayBridge.instantRange(
        fromLogicalDay: fromDay,
        throughLogicalDay: throughDay,
        timezoneName: logicalTimezoneName)
    else { return }
    _ = try await eventKitCoordinator.ingest(
      enabled: eventKitEnabled,
      accessMode: await effectiveCalendarAiAccessMode(),
      calendarFilter: eventKitCalendarFilter,
      from: instantRange.start,
      to: instantRange.endExclusive,
      windowStart: fromDay,
      windowEnd: throughDay,
      requestAccess: requestAccess)
  }

  /// The calendar AI-access tier the EventKit ingest should mirror at, read from
  /// the core's persisted `calendar_ai_access_mode` device-state so a core-side
  /// downgrade (Settings / App Intents reducing detail and purging the mirror) holds
  /// across the next refresh instead of being re-mirrored at full detail.
  ///
  /// An absent row means the device has never chosen a tier and resolves to
  /// ``CalendarAiAccessMode/defaultMode`` (`full_details`): the tier is enforced
  /// at ingest, so a stricter starting point would blind the device owner's own
  /// calendar UI along with AI reads. An unreadable or malformed row instead
  /// means the existing choice is unknown, so it resolves to
  /// ``CalendarAiAccessMode/failSafeMode`` (`busy_only`) rather than widening
  /// exposure past whatever the user may have selected.
  func effectiveCalendarAiAccessMode() async -> CalendarAiAccessMode {
    let raw: String?
    do {
      raw = try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
    } catch {
      return CalendarAiAccessMode.failSafeMode
    }
    guard let raw else { return CalendarAiAccessMode.defaultMode }
    guard let mode = CalendarAiAccessMode.parseStrict(raw) else {
      return CalendarAiAccessMode.failSafeMode
    }
    return mode
  }

  /// Read the effective device-local EventKit detail tier for Settings.
  public func calendarAccessModeFromSettings() async -> CalendarAiAccessMode {
    await effectiveCalendarAiAccessMode()
  }

  /// Persist an explicit Settings choice, then re-ingest the current window at
  /// that tier. The core owns downgrade purging and `device_state` remains the
  /// sole authority; there is no parallel UserDefaults copy.
  @discardableResult
  public func setCalendarAccessModeFromSettings(_ mode: CalendarAiAccessMode) async -> Bool {
    do {
      _ = try await core.setPreference(
        key: PreferenceKeys.devCalendarAiAccessMode,
        value: mode.asString)
    } catch {
      lastEventKitImportErrorMessage = await userFacingBannerMessage(
        for: error, source: "ios.settings.eventkit_access_mode_failed")
      eventKitSettingsRecoveryNeeded = false
      await loadRuntimeDiagnostics()
      return false
    }
    await applyEventKitSettingsFromSettings(requestAccess: false)
    return true
  }

  public func presentEventKitSettingsRecovery(_ message: String) {
    lastEventKitImportErrorMessage = message
    eventKitSettingsRecoveryNeeded = true
  }

  public func clearEventKitSettingsRecovery() {
    lastEventKitImportErrorMessage = nil
    eventKitSettingsRecoveryNeeded = false
  }

  private func eventKitIngestWindow() -> (fromDay: String, throughDay: String) {
    if let timeline = calendarTimeline {
      return (timeline.from, timeline.to)
    }
    let anchorDay = logicalTodayString
    let fromDay = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: -7) ?? anchorDay
    let throughDay = LorvexDateFormatters.ymdUTCAddingDays(anchorDay, days: 7) ?? anchorDay
    return (fromDay, throughDay)
  }

  private static var eventKitAccessDeniedMessage: String {
    String(
      localized: "settings.calendar.access_denied",
      defaultValue:
        "Calendar access is off. Open Settings to allow Lorvex to read device calendars.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private static func isEventKitReadDenied(_ error: Error) -> Bool {
    guard let accessError = error as? MobileEventKitAccessError else { return false }
    return accessError == .readAccessDenied
  }
}
