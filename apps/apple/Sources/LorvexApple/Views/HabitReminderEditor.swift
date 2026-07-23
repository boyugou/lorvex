import LorvexCore
import SwiftUI

/// Interactive Reminders section in a habit's detail pane. Reminder times render
/// as removable capsule chips (tap to retime via ``LorvexTimeChip``, `xmark` to
/// delete), with a "+ Add reminder" affordance for more times. A multi-count habit can switch to a
/// "throughout the day" window that evenly spaces `targetCount` reminders; binary
/// and times-per-week habits get a cadence-aware hint instead. Every edit routes
/// through the store's reminder-policy actions, which reload the detail and re-plan
/// the notification schedule.
///
/// Everything is inline — no sheet or popup beyond the time chips' own popover.
struct HabitReminderEditor: View {
  @Bindable var store: AppStore
  let habit: LorvexHabit
  let policies: [HabitReminderPolicy]

  /// "Specific times" vs the multi-count "throughout the day" window. Only
  /// surfaced when `targetCount > 1`; specific times is the only mode otherwise.
  @State private var mode: HabitReminderMode = .specific
  @State private var windowStart = HabitReminderTime.date(fromClock: "09:00")
  @State private var windowEnd = HabitReminderTime.date(fromClock: "21:00")

  private var sortedPolicies: [HabitReminderPolicy] {
    policies.sorted { $0.reminderTime < $1.reminderTime }
  }

  private var isMultiCount: Bool { habit.targetCount > 1 }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      header

      if isMultiCount {
        LorvexSegmentedControl(
          options: HabitReminderMode.allCases,
          selection: $mode,
          title: \.title,
          accessibilityIdentifier: "habit.reminders.mode",
          accessibilityLabel: String(
            localized: "habits.detail.reminders", defaultValue: "Reminders",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
      }

      if isMultiCount && mode == .window {
        HabitReminderWindowSection(
          store: store,
          habit: habit,
          windowStart: $windowStart,
          windowEnd: $windowEnd
        )
      } else {
        specificTimesSection
      }

      hint
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("habit.reminders.editor")
    // Seed the "throughout the day" window from the habit's existing reminder
    // span so editing a habit that already has times opens on its real window
    // instead of the generic 9:00–21:00 default. Keyed on the habit id so it
    // seeds once per habit and doesn't clobber in-session window edits when the
    // policy set reloads.
    .task(id: habit.id) { seedWindowFromExistingTimes() }
  }

  /// Sets the window editor's start/end to the earliest and latest existing
  /// reminder times. No-ops unless there are at least two distinct times to
  /// span, leaving the default window for habits with zero or one reminder.
  private func seedWindowFromExistingTimes() {
    let minutes = sortedPolicies.compactMap { HabitReminderTime.minutesOfDay($0.reminderTime) }
    guard let first = minutes.first, let last = minutes.last, last > first else { return }
    windowStart = HabitReminderTime.date(fromMinutes: first)
    windowEnd = HabitReminderTime.date(fromMinutes: last)
  }

  private var header: some View {
    Label(
      String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "bell"
    )
    .font(LorvexDesign.Typography.sectionHeader)
    .foregroundStyle(.primary)
  }

  @ViewBuilder
  private var specificTimesSection: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.s, lineSpacing: LorvexDesign.Spacing.s) {
      ForEach(sortedPolicies) { policy in
        HabitReminderChip(
          policy: policy,
          onRetime: { time in
            Task { await store.setHabitReminderTime(policy: policy, to: time, in: policies) }
          },
          onToggle: { Task { await store.toggleHabitReminderEnabled(policy: policy) } },
          onDelete: {
            Task { await store.removeHabitReminder(habitID: habit.id, policyID: policy.id) }
          }
        )
      }
      HabitReminderAddAffordance(
        idPrefix: "habit.reminders",
        suggestedTime: { HabitReminderTime.suggestedNext(after: sortedPolicies) },
        onAdd: { time in
          Task { await store.addHabitReminder(habitID: habit.id, time: time) }
        }
      )
    }
  }

  @ViewBuilder
  private var hint: some View {
    if let text = HabitReminderHint.text(for: habit, mode: mode) {
      Text(text)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("habit.reminders.hint")
    }
  }
}

/// One reminder time as a removable capsule: the `LorvexTimeChip` retimes it, the
/// `xmark` deletes it. A disabled policy renders struck-through with a quieter
/// tint; tapping its time re-enables it (the affordance for "set but off").
private struct HabitReminderChip: View {
  let policy: HabitReminderPolicy
  let onRetime: (String) -> Void
  let onToggle: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      if policy.enabled {
        LorvexTimeChip(
          date: HabitReminderTime.date(fromClock: policy.reminderTime),
          accessibilityIdentifier: "habit.reminders.chip.timeChip"
        ) { onRetime(HabitReminderTime.clock(from: $0)) }
      } else {
        Button(action: onToggle) {
          Text(HabitReminderTime.display(policy.reminderTime))
            .font(LorvexDesign.Typography.primaryText)
            .monospacedDigit()
            .strikethrough()
            .foregroundStyle(.tertiary)
            .padding(.horizontal, LorvexDesign.Spacing.s)
            .padding(.vertical, LorvexDesign.Spacing.xs)
            .background(.quaternary.opacity(0.35), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
          format: String(
            localized: "habits.reminders.reenable",
            defaultValue: "Enable reminder at %@",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          HabitReminderTime.display(policy.reminderTime)))
      }

      HabitReminderDeleteButton(onDelete: onDelete)
    }
    .accessibilityIdentifier("habit.reminders.chip")
  }
}
