import LorvexCore
import SwiftUI

/// Working-hours configuration for the mobile Settings screen: the daily
/// window the schedule proposal fits focus blocks into. Native time pickers;
/// changes persist immediately and inverted windows are rejected by the
/// store with a visible error.
struct MobileStoreSettingsWorkingHoursSection: View {
  @Bindable var store: MobileStore

  @State private var start = Date()
  @State private var end = Date()
  @State private var isLoaded = false

  var body: some View {
    Section {
      DatePicker(
        String(
          localized: "settings.working_hours.start", defaultValue: "Start", table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: $start, displayedComponents: .hourAndMinute
      )
      .accessibilityIdentifier("settings.workingHours.start")

      DatePicker(
        String(
          localized: "settings.working_hours.end", defaultValue: "End", table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: $end, displayedComponents: .hourAndMinute
      )
      .accessibilityIdentifier("settings.workingHours.end")
    } header: {
      Text(
        String(
          localized: "settings.working_hours.title", defaultValue: "Working Hours",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "settings.working_hours.caption",
          defaultValue: "Schedule proposals fit focus blocks inside this window.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    .task {
      let stored = await store.loadWorkingHoursPreference()
      start = Self.date(fromHHMM: stored.start) ?? start
      end = Self.date(fromHHMM: stored.end) ?? end
      isLoaded = true
    }
    .onChange(of: start) { _, _ in persist() }
    .onChange(of: end) { _, _ in persist() }
  }

  private func persist() {
    guard isLoaded else { return }
    let startText = Self.hhmm(from: start)
    let endText = Self.hhmm(from: end)
    Task { await store.saveWorkingHoursPreference(start: startText, end: endText) }
  }

  private static func date(fromHHMM value: String) -> Date? {
    guard let minutes = WorkingHoursPreference.minutesOfDay(value) else { return nil }
    return Calendar.current.date(
      bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())
  }

  private static func hhmm(from date: Date) -> String {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }
}
