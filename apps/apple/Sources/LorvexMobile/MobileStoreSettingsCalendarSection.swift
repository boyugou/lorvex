import EventKit
import LorvexCore
import LorvexDomain
import SwiftUI

/// The Calendar group of Settings: mirroring device calendars, what Lorvex may
/// see of their events, and which calendars it reads. The calendar list reloads
/// each time "Calendars to Mirror" opens and whenever the calendar database
/// changes, so a calendar added in another app appears without a refresh
/// action; a reload keeps the current rows on screen, and only the first load
/// shows progress.
struct MobileStoreSettingsCalendarSection: View {
  @Bindable var store: MobileStore
  @State private var calendars: [EventKitCalendarDescriptor] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var expanded = false
  @State private var pendingFilterRefresh = false
  @State private var calendarAccessMode = CalendarAiAccessMode.defaultMode
  @State private var isSettingCalendarAccessMode = false

  var body: some View {
    Section {
      Toggle(isOn: eventKitEnabledBinding) {
        VStack(alignment: .leading, spacing: 2) {
          Text(
            String(
              localized: "settings.calendar.mirror_device_calendars",
              defaultValue: "Mirror Device Calendars", table: "Localizable",
              bundle: MobileL10n.bundle))
          Text(
            String(
              localized: "settings.calendar.mirror_detail",
              defaultValue:
                "Read selected device calendars into Lorvex without writing to your personal calendars.",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
        }
      }
      .disabled(
        store.isSettingEventKitEnabled || isSettingCalendarAccessMode
          || store.isApplyingEventKitSettings)
      .accessibilityIdentifier("mobileSettings.calendar.enabled")

      Picker(
        String(
          localized: "settings.calendar.access.label",
          defaultValue: "Imported Event Details",
          table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: calendarAccessModeBinding
      ) {
        ForEach(CalendarAiAccessMode.allCases, id: \.self) { mode in
          Text(mode.mobileSettingsTitle).tag(mode)
        }
      }
      .disabled(
        isSettingCalendarAccessMode || store.isSettingEventKitEnabled
          || store.isApplyingEventKitSettings)
      .accessibilityIdentifier("mobileSettings.calendar.accessMode")
    } header: {
      Text(
        String(
          localized: "settings.section.calendar", defaultValue: "Calendar", table: "Localizable",
          bundle: MobileL10n.bundle))
    } footer: {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(calendarAccessMode.mobileSettingsDetail)
        Text(
          String(
            localized: "settings.calendar.access.scope_detail",
            defaultValue:
              "Applies to what Lorvex and connected assistants can see on this device.",
            table: "Localizable",
            bundle: MobileL10n.bundle))
      }
    }
    .task {
      calendarAccessMode = await store.calendarAccessModeFromSettings()
      await loadCalendarsIfNeeded()
      // The loop ends when the task is cancelled, as the section leaves the page.
      for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
        await loadCalendars()
      }
    }
    .onChange(of: store.eventKitEnabled) { _, enabled in
      if enabled {
        Task { await loadCalendars() }
      } else {
        calendars = []
        errorMessage = nil
      }
    }

    // The mirror filter is its own group so the access footer above stays next
    // to the picker it explains instead of trailing the calendar list.
    Section {
      if store.eventKitEnabled {
        calendarFilterGroup
      }

      if let message = displayedErrorMessage {
        Text(message)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.error)
        if shouldShowOpenSettingsCTA {
          MobileSettingsRecoveryLink(
            label: String(
              localized: "settings.calendar.open_settings", defaultValue: "Open Settings",
              table: "Localizable", bundle: MobileL10n.bundle),
            accessibilityIdentifier: "mobileSettings.calendar.openSettings")
        }
      }
    }
    .onChange(of: expanded) { _, isExpanded in
      if isExpanded {
        Task { await loadCalendars() }
      } else {
        flushPendingFilterRefresh()
      }
    }
    .onDisappear { flushPendingFilterRefresh() }
  }

  /// The mirrored-calendar picker. Shown only while mirroring is on: like the
  /// rows under a system switch in iOS Settings, it has nothing to configure
  /// while the switch is off.
  private var calendarFilterGroup: some View {
    DisclosureGroup(isExpanded: $expanded) {
      Picker(
        String(
          localized: "settings.calendar.filter.mirror", defaultValue: "Mirror",
          table: "Localizable", bundle: MobileL10n.bundle), selection: filterModeBinding
      ) {
        Text(
          String(
            localized: "settings.calendar.filter.all_except_muted",
            defaultValue: "All Except Muted", table: "Localizable", bundle: MobileL10n.bundle)
        )
        .tag(EventKitCalendarFilterMode.allExcept)
        Text(
          String(
            localized: "settings.calendar.filter.only_selected", defaultValue: "Only Selected",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
        .tag(EventKitCalendarFilterMode.onlySelected)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("mobileSettings.calendar.filterMode")

      calendarRows
    } label: {
      Label(
        String(
          localized: "settings.calendar.filter.title", defaultValue: "Calendars to Mirror",
          table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "calendar.badge.checkmark")
    }
    .disabled(calendarAccessMode == .off || store.isSettingEventKitEnabled)
    .accessibilityIdentifier("mobileSettings.calendar.filterToggle")
  }

  @ViewBuilder
  private var calendarRows: some View {
    if isLoading && calendars.isEmpty {
      ProgressView()
        .controlSize(.small)
    } else if calendars.isEmpty && displayedErrorMessage == nil {
      Text(
        String(
          localized: "settings.calendar.filter.empty", defaultValue: "No readable calendars found.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
    } else {
      ForEach(calendars) { calendar in
        Toggle(isOn: mirrorBinding(for: calendar.id)) {
          HStack(spacing: 10) {
            Circle()
              .fill(calendarSwatchColor(for: calendar.id))
              .frame(width: 12, height: 12)
              .overlay(Circle().stroke(.secondary.opacity(0.35), lineWidth: 0.5))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(userContent: calendar.title)
              if let sourceTitle = calendar.sourceTitle {
                Text(sourceTitle)
                  .font(LorvexDesign.Typography.tertiaryText)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .accessibilityIdentifier("mobileSettings.calendar.calendar.\(calendar.id)")
      }
    }
  }

  private var eventKitEnabledBinding: Binding<Bool> {
    Binding(
      get: { store.eventKitEnabled },
      set: { enabled in
        guard !store.isSettingEventKitEnabled else { return }
        Task { await store.setEventKitEnabledFromSettings(enabled) }
      }
    )
  }

  private var calendarAccessModeBinding: Binding<CalendarAiAccessMode> {
    Binding(
      get: { calendarAccessMode },
      set: { mode in
        guard !isSettingCalendarAccessMode else { return }
        calendarAccessMode = mode
        isSettingCalendarAccessMode = true
        Task { @MainActor in
          let stored = await store.setCalendarAccessModeFromSettings(mode)
          if !stored {
            calendarAccessMode = await store.calendarAccessModeFromSettings()
          }
          isSettingCalendarAccessMode = false
          if stored, mode.includesProvider, store.eventKitEnabled {
            await loadCalendars()
          }
        }
      })
  }

  private var filterModeBinding: Binding<EventKitCalendarFilterMode> {
    Binding(
      get: { store.eventKitCalendarFilterMode },
      set: { mode in
        store.setEventKitCalendarFilterModeFromSettings(mode)
        if mode == .onlySelected && store.eventKitIncludedCalendarIDs.isEmpty {
          store.setEventKitIncludedCalendarIDsFromSettings(Set(calendars.map(\.id)))
        }
        pendingFilterRefresh = true
      }
    )
  }

  private func mirrorBinding(for calendarID: String) -> Binding<Bool> {
    Binding(
      get: {
        switch store.eventKitCalendarFilterMode {
        case .allExcept:
          !store.eventKitExcludedCalendarIDs.contains(calendarID)
        case .onlySelected:
          store.eventKitIncludedCalendarIDs.contains(calendarID)
        }
      },
      set: { isMirrored in
        switch store.eventKitCalendarFilterMode {
        case .allExcept:
          var ids = store.eventKitExcludedCalendarIDs
          if isMirrored {
            ids.remove(calendarID)
          } else {
            ids.insert(calendarID)
          }
          store.setEventKitExcludedCalendarIDsFromSettings(ids)
        case .onlySelected:
          var ids = store.eventKitIncludedCalendarIDs
          if isMirrored {
            ids.insert(calendarID)
          } else {
            ids.remove(calendarID)
          }
          store.setEventKitIncludedCalendarIDsFromSettings(ids)
        }
        pendingFilterRefresh = true
      }
    )
  }

  private var displayedErrorMessage: String? {
    errorMessage ?? store.lastEventKitImportErrorMessage
  }

  private var shouldShowOpenSettingsCTA: Bool {
    displayedErrorMessage != nil || store.eventKitSettingsRecoveryNeeded
  }

  private func loadCalendarsIfNeeded() async {
    guard calendars.isEmpty, store.eventKitEnabled else { return }
    await loadCalendars()
  }

  private func loadCalendars() async {
    guard store.eventKitEnabled else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      calendars = try await store.loadEventKitCalendars()
      errorMessage = nil
    } catch {
      if store.eventKitSettingsRecoveryNeeded {
        errorMessage = nil
      } else {
        errorMessage = String(
          localized: "settings.calendar.load_error",
          defaultValue: "Couldn’t load calendars. Check calendar access in Settings.",
          table: "Localizable", bundle: MobileL10n.bundle)
      }
    }
  }

  private func flushPendingFilterRefresh() {
    guard pendingFilterRefresh else { return }
    pendingFilterRefresh = false
    Task { await store.applyEventKitSettingsFromSettings(requestAccess: false) }
  }

  private func calendarSwatchColor(for calendarID: String) -> Color {
    let scalars = calendarID.unicodeScalars.reduce(0) { partial, scalar in
      partial &* 31 &+ Int(scalar.value)
    }
    return Color(
      // `.magnitude` (UInt), not `abs()`: the wrapping hash can equal Int.min,
      // for which `abs()` is a hard runtime trap.
      hue: Double(scalars.magnitude % 360) / 360,
      saturation: 0.62,
      brightness: 0.82)
  }
}

extension CalendarAiAccessMode {
  fileprivate var mobileSettingsTitle: String {
    switch self {
    case .off:
      String(
        localized: "settings.calendar.access.off", defaultValue: "Off",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .busyOnly:
      String(
        localized: "settings.calendar.access.busy_only", defaultValue: "Busy Only",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .fullDetails:
      String(
        localized: "settings.calendar.access.full_details", defaultValue: "Full Details",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  fileprivate var mobileSettingsDetail: String {
    switch self {
    case .off:
      String(
        localized: "settings.calendar.access.off_detail",
        defaultValue: "No calendar events are read into Lorvex.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .busyOnly:
      String(
        localized: "settings.calendar.access.busy_only_detail",
        defaultValue:
          "Mirror occupied time only — event titles, locations, and notes are hidden.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .fullDetails:
      String(
        localized: "settings.calendar.access.full_details_detail",
        defaultValue: "Mirror full event details, including titles, locations, and notes.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}
