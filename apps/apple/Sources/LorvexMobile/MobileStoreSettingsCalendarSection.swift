import LorvexCore
import LorvexDomain
import SwiftUI

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
    Section(
      String(
        localized: "settings.section.calendar", defaultValue: "Calendar", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      Toggle(isOn: eventKitEnabledBinding) {
        Label {
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
        } icon: {
          Image(systemName: "calendar")
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

      Text(calendarAccessMode.mobileSettingsDetail)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)

      Text(
        String(
          localized: "settings.calendar.access.scope_detail",
          defaultValue:
            "Applies to what Lorvex and connected assistants can see on this device.",
          table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)

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

        Button(
          String(
            localized: "settings.calendar.filter.refresh", defaultValue: "Refresh Calendars",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          Task { await loadCalendars() }
        }
        .disabled(isLoading || !store.eventKitEnabled || store.isApplyingEventKitSettings)
        .accessibilityIdentifier("mobileSettings.calendar.refresh")
      } label: {
        Label(
          String(
            localized: "settings.calendar.filter.title", defaultValue: "Calendars to Mirror",
            table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "calendar.badge.checkmark")
      }
      .disabled(
        !store.eventKitEnabled || calendarAccessMode == .off
          || store.isSettingEventKitEnabled
      )
      .accessibilityIdentifier("mobileSettings.calendar.filterToggle")

      if let message = displayedErrorMessage {
        Text(message)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.red)
        if shouldShowOpenSettingsCTA {
          MobileSettingsRecoveryLink(
            label: String(
              localized: "settings.calendar.open_settings", defaultValue: "Open Settings",
              table: "Localizable", bundle: MobileL10n.bundle),
            accessibilityIdentifier: "mobileSettings.calendar.openSettings")
        }
      }
    }
    .task {
      calendarAccessMode = await store.calendarAccessModeFromSettings()
      await loadCalendarsIfNeeded()
    }
    .onChange(of: store.eventKitEnabled) { _, enabled in
      if enabled {
        Task { await loadCalendars() }
      } else {
        calendars = []
        errorMessage = nil
      }
    }
    .onChange(of: expanded) { _, isExpanded in
      if !isExpanded { flushPendingFilterRefresh() }
    }
    .onDisappear { flushPendingFilterRefresh() }
  }

  @ViewBuilder
  private var calendarRows: some View {
    if isLoading {
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
              Text(calendar.title)
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
          defaultValue: "Couldn't load calendars. Check calendar access in Settings.",
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
      hue: Double(abs(scalars) % 360) / 360,
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
