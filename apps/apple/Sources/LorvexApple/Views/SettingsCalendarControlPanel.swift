import LorvexCore
import LorvexDomain
import SwiftUI

/// What Lorvex may see of the calendars: how much of each imported event it
/// mirrors, with what that level means as the footer directly under it, then
/// which calendars it reads (``EventKitCalendarFilterPicker``), in a group of
/// its own since its rows unfold below it.
struct SettingsCalendarControlPanel: View {
  @Bindable var settings: AppSettingsStore
  @Bindable var store: AppStore
  @State private var calendarAccessMode = CalendarAiAccessMode.defaultMode
  @State private var isSettingCalendarAccessMode = false

  var body: some View {
    Section {
      Picker(selection: calendarAccessModeBinding) {
        ForEach(CalendarAiAccessMode.allCases, id: \.self) { mode in
          Text(mode.macSettingsTitle).tag(mode)
        }
      } label: {
        Text(
          String(
            localized: "settings.calendar.access.label",
            defaultValue: "Imported Event Details",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
      }
      .disabled(isSettingCalendarAccessMode)
      .accessibilityIdentifier("settings.eventkit.accessMode")
    } footer: {
      // What the chosen level mirrors, then whom it applies to, as one
      // paragraph.
      Text(verbatim: "\(calendarAccessMode.macSettingsDetail) \(Self.scopeDetail)")
        .accessibilityIdentifier("settings.calendar.accessDetail")
    }
    .task {
      calendarAccessMode = await store.calendarAccessModeFromSettings()
    }

    Section {
      EventKitCalendarFilterPicker(settings: settings, store: store)
        .disabled(!settings.eventKitEnabled || calendarAccessMode == .off)
        .accessibilityIdentifier("settings.calendar.filterPanel")
    }
  }

  private static var scopeDetail: String {
    String(
      localized: "settings.calendar.access.scope_detail",
      defaultValue: "Applies to what Lorvex and connected assistants can see on this device.",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  private var calendarAccessModeBinding: Binding<CalendarAiAccessMode> {
    Binding(
      get: { calendarAccessMode },
      set: { mode in
        guard !isSettingCalendarAccessMode else { return }
        calendarAccessMode = mode
        isSettingCalendarAccessMode = true
        Task { @MainActor in
          let stored = await store.setCalendarAccessModeFromSettings(
            mode,
            enabled: settings.eventKitEnabled)
          if !stored {
            calendarAccessMode = await store.calendarAccessModeFromSettings()
          }
          isSettingCalendarAccessMode = false
        }
      })
  }
}

extension CalendarAiAccessMode {
  fileprivate var macSettingsTitle: String {
    switch self {
    case .off:
      String(
        localized: "settings.calendar.access.off", defaultValue: "Off",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .busyOnly:
      String(
        localized: "settings.calendar.access.busy_only", defaultValue: "Busy Only",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .fullDetails:
      String(
        localized: "settings.calendar.access.full_details", defaultValue: "Full Details",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  fileprivate var macSettingsDetail: String {
    switch self {
    case .off:
      String(
        localized: "settings.calendar.access.off_detail",
        defaultValue: "No calendar events are read into Lorvex.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .busyOnly:
      String(
        localized: "settings.calendar.access.busy_only_detail",
        defaultValue:
          "Mirror occupied time only — event titles, locations, and notes are hidden.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .fullDetails:
      String(
        localized: "settings.calendar.access.full_details_detail",
        defaultValue: "Mirror full event details, including titles, locations, and notes.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
