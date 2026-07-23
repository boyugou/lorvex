import LorvexCore
import SwiftUI

/// Create-time reminder control for the New Habit sheet. Collects the reminder
/// times ("HH:mm") the habit is armed with the moment it's created; each becomes
/// an enabled reminder policy in ``AppStore/createDraftHabit()``.
///
/// Mirrors the detail inspector's specific-times section — removable time chips
/// plus an "Add reminder" affordance — but writes to the create draft rather
/// than a live habit. There is no "throughout the day" window generator or
/// per-reminder enable toggle here; those need a persisted habit and live in
/// ``HabitReminderEditor`` once it exists.
struct HabitDraftReminderField: View {
  @Bindable var store: AppStore

  @State private var draftTime = HabitReminderTime.date(fromClock: "09:00")
  @State private var isAddingTime = false

  private var sortedTimes: [String] {
    store.draftHabitReminderTimes.sorted {
      (HabitReminderTime.minutesOfDay($0) ?? 0) < (HabitReminderTime.minutesOfDay($1) ?? 0)
    }
  }

  var body: some View {
    DraftSheetPanel(accessibilityIdentifier: "createHabit.reminders") {
      DraftSheetField(
        title: String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "bell"
      ) {
        LorvexFlowLayout(spacing: LorvexDesign.Spacing.s, lineSpacing: LorvexDesign.Spacing.s) {
          ForEach(sortedTimes, id: \.self) { time in
            chip(time)
          }
          addAffordance
        }
      }
    }
  }

  private func chip(_ time: String) -> some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      LorvexTimeChip(
        date: HabitReminderTime.date(fromClock: time),
        accessibilityIdentifier: "createHabit.reminders.chip.timeChip"
      ) { retime(from: time, to: HabitReminderTime.clock(from: $0)) }

      Button { remove(time) } label: {
        Image(systemName: "xmark")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(4)
          .background(.quaternary.opacity(0.4), in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .accessibilityIdentifier("createHabit.reminders.chip")
  }

  @ViewBuilder
  private var addAffordance: some View {
    if isAddingTime {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        LorvexTimeChip(date: draftTime, accessibilityIdentifier: "createHabit.reminders.add.timeChip") {
          draftTime = $0
        }
        Button {
          add(HabitReminderTime.clock(from: draftTime))
          isAddingTime = false
        } label: {
          Image(systemName: "checkmark")
        }
        .buttonStyle(.lorvex(.primary))
        .accessibilityLabel(String(
          localized: "habits.reminders.add", defaultValue: "Add Reminder",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("createHabit.reminders.add.confirm")
        Button { isAddingTime = false } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.lorvexNeutral)
        .accessibilityLabel(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    } else {
      Button {
        draftTime = suggestedNext()
        isAddingTime = true
      } label: {
        Label(
          String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus"
        )
      }
      .buttonStyle(.lorvexSecondary)
      .accessibilityIdentifier("createHabit.reminders.add")
    }
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

  /// An hour after the latest existing draft time (wrapping within the day), else
  /// 9:00 — the same suggestion the live editor makes for a fresh reminder.
  private func suggestedNext() -> Date {
    guard
      let latest = store.draftHabitReminderTimes
        .compactMap({ HabitReminderTime.minutesOfDay($0) }).max()
    else {
      return HabitReminderTime.date(fromClock: "09:00")
    }
    return HabitReminderTime.date(fromMinutes: (latest + 60) % (24 * 60))
  }
}
