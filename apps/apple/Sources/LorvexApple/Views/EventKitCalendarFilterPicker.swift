import LorvexCore
import SwiftUI

struct EventKitCalendarFilterPicker: View {
  @Bindable var settings: AppSettingsStore
  @Bindable var store: AppStore
  @State private var calendars: [EventKitCalendarDescriptor] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var expanded = false
  /// A filter change persists to settings immediately, but the EventKit
  /// re-ingest it triggers is expensive. Toggling several calendars in a row
  /// should mirror once, not once per toggle, so defer the re-ingest until the
  /// picker collapses (or disappears) and run a single refresh then.
  @State private var pendingFilterRefresh = false

  var body: some View {
    // Plain Button, not DisclosureGroup: the native disclosure triangle drops
    // its first click in a freshly shown grouped Form (see SettingsMCPSections
    // for the reference pattern).
    Button {
      withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Label(String(localized: "settings.calendar.filter.title", defaultValue: "Calendars to Mirror", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "calendar.badge.checkmark")
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(expanded ? 90 : 0))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("settings.calendar.filterToggle")
    .accessibilityAddTraits(.isHeader)
    .task { await loadCalendarsIfNeeded() }
    .onChange(of: settings.eventKitEnabled) { _, enabled in
      guard enabled else {
        calendars = []
        errorMessage = nil
        return
      }
      Task { await loadCalendars() }
    }
    .onChange(of: expanded) { _, isExpanded in
      if !isExpanded { flushPendingFilterRefresh() }
    }
    .onDisappear { flushPendingFilterRefresh() }

    if expanded {
      Picker(String(localized: "settings.calendar.filter.mirror", defaultValue: "Mirror", table: "Localizable", bundle: LorvexL10n.bundle), selection: filterModeBinding) {
        Text(LocalizedStringResource("settings.calendar.filter.all_except_muted", defaultValue: "All Except Muted", table: "Localizable", bundle: LorvexL10n.bundle)).tag(EventKitCalendarFilterMode.allExcept)
        Text(LocalizedStringResource("settings.calendar.filter.only_selected", defaultValue: "Only Selected", table: "Localizable", bundle: LorvexL10n.bundle)).tag(EventKitCalendarFilterMode.onlySelected)
      }
      .pickerStyle(.segmented)
      // Disabled while calendars load: switching to "Only Selected" seeds the
      // include set from the loaded calendars (below), so switching before they
      // load would seed an empty set — which now means "mirror nothing", not
      // "mirror all" — and silently stop mirroring.
      .disabled(isLoading)
      .accessibilityIdentifier("settings.eventkit.calendarFilterMode")

      calendarRows

      if let errorMessage {
        Text(errorMessage)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.red)
      }

      Button(String(localized: "settings.calendar.filter.refresh", defaultValue: "Refresh Calendars", table: "Localizable", bundle: LorvexL10n.bundle)) {
        Task { await loadCalendars() }
      }
      .disabled(isLoading)
    }
  }

  @ViewBuilder
  private var calendarRows: some View {
    if isLoading {
      ProgressView()
        .controlSize(.small)
    } else if calendars.isEmpty {
      Text(LocalizedStringResource("settings.calendar.filter.empty", defaultValue: "No readable calendars found.", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    } else {
      ForEach(calendars) { calendar in
        Toggle(isOn: mirrorBinding(for: calendar.id)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(calendar.title)
            if let source = calendar.sourceTitle {
              Text(source)
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
            }
          }
        }
        .accessibilityIdentifier("settings.eventkit.calendar.\(calendar.id)")
      }
    }
  }

  private var filterModeBinding: Binding<EventKitCalendarFilterMode> {
    Binding(
      get: { settings.eventKitCalendarFilterMode },
      set: { mode in
        settings.eventKitCalendarFilterMode = mode
        switch mode {
        case .allExcept:
          settings.eventKitIncludedCalendarIDs = []
        case .onlySelected:
          settings.eventKitExcludedCalendarIDs = []
          if settings.eventKitIncludedCalendarIDs.isEmpty {
            settings.eventKitIncludedCalendarIDs = Set(calendars.map(\.id))
          }
        }
        pendingFilterRefresh = true
      }
    )
  }

  private func mirrorBinding(for calendarID: String) -> Binding<Bool> {
    Binding(
      get: {
        switch settings.eventKitCalendarFilterMode {
        case .allExcept:
          !settings.eventKitExcludedCalendarIDs.contains(calendarID)
        case .onlySelected:
          settings.eventKitIncludedCalendarIDs.contains(calendarID)
        }
      },
      set: { isMirrored in
        switch settings.eventKitCalendarFilterMode {
        case .allExcept:
          if isMirrored {
            settings.eventKitExcludedCalendarIDs.remove(calendarID)
          } else {
            settings.eventKitExcludedCalendarIDs.insert(calendarID)
          }
        case .onlySelected:
          if isMirrored {
            settings.eventKitIncludedCalendarIDs.insert(calendarID)
          } else {
            settings.eventKitIncludedCalendarIDs.remove(calendarID)
          }
        }
        pendingFilterRefresh = true
      }
    )
  }

  private func loadCalendarsIfNeeded() async {
    guard calendars.isEmpty, settings.eventKitEnabled else { return }
    await loadCalendars()
  }

  private func loadCalendars() async {
    guard settings.eventKitEnabled else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      calendars = try await store.loadEventKitCalendars()
      errorMessage = nil
    } catch {
      // Surface an actionable hint rather than the raw EventKit error; a failed
      // load is virtually always missing calendar access.
      errorMessage = String(
        localized: "calendar.picker.load_error",
        defaultValue: "Couldn’t load your calendars. Check that Lorvex has calendar access in System Settings.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }

  /// Run the deferred re-ingest once if any filter toggle is pending. Called
  /// when the picker collapses or disappears so a batch of toggles mirrors once.
  private func flushPendingFilterRefresh() {
    guard pendingFilterRefresh else { return }
    pendingFilterRefresh = false
    Task { await applySettings() }
  }

  private func applySettings() async {
    await store.applyEventKitSettings(enabled: settings.eventKitEnabled)
  }
}
