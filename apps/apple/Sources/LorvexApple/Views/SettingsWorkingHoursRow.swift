import LorvexCore
import SwiftUI

/// Settings control for the `working_hours` preference: the daily window each
/// day's load is measured against (the week grid's captions, the iPhone Plan
/// strips, Today's overbooked headline), and that the schedule proposal (the
/// app's Suggest Times and the assistant's propose_daily_schedule alike) keeps
/// suggested task times inside. One row holds the window as two time chips,
/// start – end, in a group of its own so its explanation is the footer
/// directly under it. Changes persist immediately; the store rejects an
/// invalid window (end at or before start) with a visible error, and the
/// chips go back to the saved window.
struct SettingsWorkingHoursRow: View {
  @Bindable var store: AppStore

  @State private var start = Date()
  @State private var end = Date()
  /// The last window the store accepted, which a rejected window puts the
  /// chips back on.
  @State private var savedStart = Date()
  @State private var savedEnd = Date()
  @State private var isLoaded = false

  var body: some View {
    Section {
      LabeledContent(String(localized: "settings.working_hours.title", defaultValue: "Day Hours", table: "Localizable", bundle: LorvexL10n.bundle)) {
        HStack(spacing: LorvexDesign.Spacing.xs) {
          LorvexTimeChip(
            date: start,
            accessibilityIdentifier: "settings.workingHours.start",
            accessibilityName: String(localized: "settings.working_hours.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle)
          ) {
            start = $0
            persist()
          }
          Text(verbatim: "–")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          LorvexTimeChip(
            date: end,
            accessibilityIdentifier: "settings.workingHours.end",
            accessibilityName: String(localized: "settings.working_hours.end", defaultValue: "End", table: "Localizable", bundle: LorvexL10n.bundle)
          ) {
            end = $0
            persist()
          }
        }
      }
    } footer: {
      Text(LocalizedStringResource(
        "settings.working_hours.caption",
        defaultValue: "Lorvex plans your tasks into these hours. It judges how full a day is against them, and suggested times stay inside them.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
    .task {
      let stored = await store.loadWorkingHoursPreference()
      start = Self.date(fromHHMM: stored.start) ?? start
      end = Self.date(fromHHMM: stored.end) ?? end
      savedStart = start
      savedEnd = end
      isLoaded = true
    }
    .accessibilityIdentifier("settings.workingHours")
  }

  /// Persist the window after a user edit (the time chips call this directly).
  /// Nothing is written before the stored window has loaded or when the edit
  /// leaves the saved window unchanged. A window the store rejects puts the
  /// chips back on the saved one, unless another edit has replaced it since.
  private func persist() {
    guard isLoaded else { return }
    let startText = Self.hhmm(from: start)
    let endText = Self.hhmm(from: end)
    guard startText != Self.hhmm(from: savedStart) || endText != Self.hhmm(from: savedEnd) else {
      return
    }
    let newStart = start
    let newEnd = end
    Task {
      if await store.saveWorkingHoursPreference(start: startText, end: endText) {
        savedStart = newStart
        savedEnd = newEnd
      } else if start == newStart, end == newEnd {
        start = savedStart
        end = savedEnd
      }
    }
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
