import LorvexCore
import SwiftUI

/// Working-hours configuration for the mobile Settings screen: the daily
/// window each day's load is measured against (the Plan week strips, Today's
/// overbooked headline), and that the schedule proposal keeps suggested task
/// times inside. Native time pickers; a change persists once the pickers come
/// to rest, and an inverted window is rejected by the store with a visible
/// error.
struct MobileStoreSettingsWorkingHoursSection: View {
  @Bindable var store: MobileStore

  @State private var start = Date()
  @State private var end = Date()
  @State private var isLoaded = false
  /// The last window the store accepted. A rejected inverted window reverts the
  /// pickers here so they never sit on an unsaved, invalid selection.
  @State private var savedStart = Date()
  @State private var savedEnd = Date()
  /// The save waiting for the pickers to come to rest. A wheel turn changes the
  /// selection many times; each change cancels the previous wait, so one turn
  /// is one write (and one error, should it fail) rather than one per step,
  /// and a window that is inverted only mid-turn is never saved or reported.
  @State private var pendingSave: Task<Void, Never>?

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
          localized: "settings.working_hours.title", defaultValue: "Day Hours",
          table: "Localizable", bundle: MobileL10n.bundle))
    } footer: {
      Text(
        String(
          localized: "settings.working_hours.caption",
          defaultValue: "The hours Lorvex plans your tasks into. How full a day is counts against them, and suggested times stay inside them.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    .task {
      let stored = await store.loadWorkingHoursPreference()
      start = Self.date(fromHHMM: stored.start) ?? start
      end = Self.date(fromHHMM: stored.end) ?? end
      savedStart = start
      savedEnd = end
      isLoaded = true
    }
    .onChange(of: start) { _, _ in persist() }
    .onChange(of: end) { _, _ in persist() }
  }

  private func persist() {
    guard isLoaded else { return }
    // A newer selection replaces any save still waiting, including a turn
    // that comes back to the saved window, which then saves nothing.
    pendingSave?.cancel()
    pendingSave = nil
    let startText = Self.hhmm(from: start)
    let endText = Self.hhmm(from: end)
    // Skip a no-op write. The load assigns `start`/`end` and flips `isLoaded` in
    // one synchronous batch, so `.onChange` fires with `isLoaded` already true;
    // without this guard every Settings appearance would re-persist the loaded
    // window — a spurious synced write plus a phantom `ai_changelog` row.
    guard startText != Self.hhmm(from: savedStart) || endText != Self.hhmm(from: savedEnd) else {
      return
    }
    // Snapshot the last accepted window so a rejected save can restore it. The
    // revert mutates `start`/`end` back to these already-valid values, which
    // re-fires `persist()` once and settles (idempotent), without looping.
    let revertStart = savedStart
    let revertEnd = savedEnd
    let newStart = start
    let newEnd = end
    pendingSave = Task {
      try? await Task.sleep(for: Self.restDelay)
      guard !Task.isCancelled else { return }
      if await store.saveWorkingHoursPreference(start: startText, end: endText) {
        savedStart = newStart
        savedEnd = newEnd
      } else {
        start = revertStart
        end = revertEnd
      }
    }
  }

  /// How long the pickers stay unchanged before the window is saved.
  private static let restDelay: Duration = .milliseconds(600)

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
