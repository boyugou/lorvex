import LorvexCore
import SwiftUI

/// The New Habit sheet's Reminders section. Collects the reminder times
/// ("HH:mm") the habit is armed with the moment it is created; each becomes an
/// enabled reminder policy in ``AppStore/createDraftHabit()``.
///
/// One row per time, retimed in place through its time chip and removed by
/// its trailing clear button; Add Reminder appends a row at the next free
/// time, an hour after the latest (9:00 for the first). Spreading reminders
/// through the day needs a saved habit, so it lives in the habit inspector's
/// ``HabitReminderEditor``.
struct HabitDraftReminderField: View {
  @Bindable var store: AppStore

  private var sortedTimes: [String] {
    store.draftHabitReminderTimes.sorted {
      (HabitReminderTime.minutesOfDay($0) ?? 0) < (HabitReminderTime.minutesOfDay($1) ?? 0)
    }
  }

  var body: some View {
    Section {
      ForEach(sortedTimes, id: \.self) { time in
        row(time)
      }
      Button {
        add(HabitReminderTime.nextFreeClock(after: store.draftHabitReminderTimes))
      } label: {
        Label(
          String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .accessibilityIdentifier("createHabit.reminders.add")
    } header: {
      Text(LocalizedStringResource(
        "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable",
        bundle: LorvexL10n.bundle))
    }
    .accessibilityIdentifier("createHabit.reminders")
  }

  private func row(_ time: String) -> some View {
    HStack {
      LorvexTimeChip(
        date: HabitReminderTime.date(fromClock: time),
        accessibilityIdentifier: "createHabit.reminders.chip.timeChip"
      ) { retime(from: time, to: HabitReminderTime.clock(from: $0)) }
      Spacer(minLength: LorvexDesign.Spacing.s)
      Button { remove(time) } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help(String(localized: "habits.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "habits.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .accessibilityIdentifier("createHabit.reminders.chip")
  }

  // MARK: Draft mutation

  /// Append a reminder time, deduping by clock string (stored order is
  /// irrelevant — the view sorts for display and the create action arms each).
  private func add(_ time: String) {
    guard !store.draftHabitReminderTimes.contains(time) else { return }
    store.draftHabitReminderTimes.append(time)
  }

  private func remove(_ time: String) {
    store.draftHabitReminderTimes.removeAll { $0 == time }
  }

  /// Move a chip's time. Retiming onto a slot another chip already holds
  /// collapses to that single reminder (drop the old one) rather than leaving a
  /// duplicate the create action would upsert twice.
  private func retime(from old: String, to new: String) {
    guard old != new else { return }
    guard !store.draftHabitReminderTimes.contains(new) else {
      remove(old)
      return
    }
    if let index = store.draftHabitReminderTimes.firstIndex(of: old) {
      store.draftHabitReminderTimes[index] = new
    }
  }
}
