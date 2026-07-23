import LorvexCore
import SwiftUI

/// Settings control for the `working_hours` preference: the daily window the
/// schedule proposal (app button and the assistant's propose_daily_schedule
/// alike) fits focus blocks into. Native hour-and-minute pickers; changes
/// persist immediately and invalid windows (end at/before start) are rejected
/// by the store with a visible error.
struct SettingsWorkingHoursRow: View {
  @Bindable var store: AppStore

  @State private var start = Date()
  @State private var end = Date()
  @State private var isLoaded = false

  var body: some View {
    Section(String(localized: "settings.working_hours.title", defaultValue: "Working Hours", table: "Localizable", bundle: LorvexL10n.bundle)) {
      LabeledContent(String(localized: "settings.working_hours.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle)) {
        LorvexTimeChip(date: start, accessibilityIdentifier: "settings.workingHours.start") {
          start = $0
          persist()
        }
      }

      LabeledContent(String(localized: "settings.working_hours.end", defaultValue: "End", table: "Localizable", bundle: LorvexL10n.bundle)) {
        LorvexTimeChip(date: end, accessibilityIdentifier: "settings.workingHours.end") {
          end = $0
          persist()
        }
      }

      Text(LocalizedStringResource(
        "settings.working_hours.caption",
        defaultValue: "Schedule proposals fit focus blocks inside this window.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
    }
    .task {
      let stored = await store.loadWorkingHoursPreference()
      start = Self.date(fromHHMM: stored.start) ?? start
      end = Self.date(fromHHMM: stored.end) ?? end
      isLoaded = true
    }
    .accessibilityIdentifier("settings.workingHours")
  }

  /// Persist the window after a user edit (the time chips call this directly).
  /// The `isLoaded` guard drops the initial load's assignments so opening
  /// Settings never re-saves the value it just read back.
  private func persist() {
    guard isLoaded else { return }
    let startText = Self.hhmm(from: start)
    let endText = Self.hhmm(from: end)
    Task { await store.saveWorkingHoursPreference(start: startText, end: endText) }
  }

  private static func date(fromHHMM value: String) -> Date? {
    guard let minutes = AppStore.minutesOfDay(value) else { return nil }
    return Calendar.current.date(
      bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())
  }

  private static func hhmm(from date: Date) -> String {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }
}
