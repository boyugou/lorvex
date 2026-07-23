import LorvexCore
import LorvexDomain
import SwiftUI

// MARK: - Two-Way Calendar Sync control panel

struct SettingsCalendarControlPanel: View {
  @Bindable var settings: AppSettingsStore
  @Bindable var store: AppStore
  @State private var calendarAccessMode = CalendarAiAccessMode.defaultMode
  @State private var isSettingCalendarAccessMode = false

  var body: some View {
    Group {
      Toggle(isOn: $settings.eventKitEnabled) {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(
              LocalizedStringResource(
                "settings.calendar.two_way_sync", defaultValue: "Two-Way Calendar Sync",
                table: "Localizable", bundle: LorvexL10n.bundle))
            Text(
              LocalizedStringResource(
                "settings.calendar.two_way_detail",
                defaultValue:
                  "Read your calendar events into Lorvex and write Lorvex-scheduled blocks into a dedicated \"Lorvex\" calendar — never your personal calendars.",
                table: "Localizable",
                bundle: LorvexL10n.bundle
              )
            )
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        } icon: {
          Image(systemName: "calendar")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.accentColor)
        }
      }
      .accessibilityIdentifier("settings.eventkit.enabled")
      .onChange(of: settings.eventKitEnabled) { _, enabled in
        Task {
          if enabled {
            let granted = await store.requestCalendarAccessFromSettings()
            guard granted else {
              settings.eventKitEnabled = false
              return
            }
          }
          await store.applyEventKitSettings(enabled: enabled)
        }
      }

      Picker(selection: calendarAccessModeBinding) {
        ForEach(CalendarAiAccessMode.allCases, id: \.self) { mode in
          Text(mode.macSettingsTitle).tag(mode)
        }
      } label: {
        Label(
          String(
            localized: "settings.calendar.access.label",
            defaultValue: "Imported Event Details",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "eye")
      }
      .disabled(isSettingCalendarAccessMode)
      .accessibilityIdentifier("settings.eventkit.accessMode")

      Text(calendarAccessMode.macSettingsDetail)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("settings.calendar.accessDetail")

      Text(
        String(
          localized: "settings.calendar.access.scope_detail",
          defaultValue:
            "Applies to what Lorvex and connected assistants can see on this device.",
          table: "Localizable",
          bundle: LorvexL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      EventKitCalendarFilterPicker(settings: settings, store: store)
        .disabled(!settings.eventKitEnabled || calendarAccessMode == .off)
        .accessibilityIdentifier("settings.calendar.filterPanel")

      Button {
        Task {
          await store.applyEventKitSettings(enabled: settings.eventKitEnabled)
        }
      } label: {
        Label(
          String(
            localized: "settings.calendar.ingest_now", defaultValue: "Ingest Now",
            table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.down.circle"
        )
      }
      .accessibilityIdentifier("settings.eventkit.ingestNow")
      .disabled(!settings.eventKitEnabled || calendarAccessMode == .off)
    }
    .task {
      calendarAccessMode = await store.calendarAccessModeFromSettings()
    }
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
