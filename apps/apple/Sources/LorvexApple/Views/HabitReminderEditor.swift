import LorvexCore
import SwiftUI

/// The popover behind a habit's Reminder field, laid out like the task
/// inspector's reminders editor: the habit's reminder times, one row each,
/// then Add Reminder.
///
/// Each row retimes its reminder in a clock field and removes it with a
/// trailing button; a reminder switched off elsewhere shows a Turn On button.
/// Add Reminder adds one at the next free time, an hour after the latest
/// (9:00 for the first), which its new row's clock field then adjusts.
/// A habit counted several times a day can instead spread its reminders
/// "throughout the day": a start and an end time that the editor fills with
/// one reminder per check-in, evenly spaced. The header's hint says when the
/// reminders fire for this habit's cadence.
///
/// Every change saves at once through the store's reminder-policy actions,
/// which reload the inspector's detail and plan the notifications again. A
/// retime saves once its clock field rests for a moment, or when the popover
/// closes, so stepping through the hours writes once.
struct HabitReminderEditor: View {
  @Bindable var store: AppStore
  let habit: LorvexHabit
  let policies: [HabitReminderPolicy]

  /// "Specific times" or the multi-count "throughout the day" window; only a
  /// habit counted several times a day offers the window.
  @State private var mode: HabitReminderMode = .specific
  @State private var windowStart = HabitReminderTime.date(fromClock: "09:00")
  @State private var windowEnd = HabitReminderTime.date(fromClock: "21:00")

  private var sortedPolicies: [HabitReminderPolicy] {
    policies.sorted { $0.reminderTime < $1.reminderTime }
  }

  private var isMultiCount: Bool { habit.targetCount > 1 }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      InspectorEditorHeader(
        title: String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
        hint: HabitReminderHint.text(for: habit, mode: mode))

      if isMultiCount {
        Picker(selection: $mode) {
          ForEach(HabitReminderMode.allCases, id: \.self) { value in
            Text(value.title).tag(value)
          }
        } label: {
          Text(String(localized: "habits.detail.reminders", defaultValue: "Reminders", table: "Localizable", bundle: LorvexL10n.bundle))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("habit.reminders.mode")
      }

      if isMultiCount && mode == .window {
        HabitReminderWindowSection(
          store: store, habit: habit, windowStart: $windowStart, windowEnd: $windowEnd)
      } else {
        specificTimes
      }
    }
    .frame(width: 300, alignment: .leading)
    .accessibilityIdentifier("habit.reminders.editor")
    .onAppear { seedWindowFromExistingTimes() }
  }

  /// Sets the window's start and end to the earliest and latest reminder
  /// times, so a habit that already has reminders opens on its real window
  /// rather than 9:00–21:00. Leaves the default for fewer than two distinct
  /// times.
  private func seedWindowFromExistingTimes() {
    let minutes = sortedPolicies.compactMap { HabitReminderTime.minutesOfDay($0.reminderTime) }
    guard let first = minutes.first, let last = minutes.last, last > first else { return }
    windowStart = HabitReminderTime.date(fromMinutes: first)
    windowEnd = HabitReminderTime.date(fromMinutes: last)
  }

  @ViewBuilder
  private var specificTimes: some View {
    if !sortedPolicies.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(sortedPolicies) { policy in
          HabitReminderTimeRow(
            policy: policy,
            retime: { time in
              guard !policies.contains(where: { $0.id != policy.id && $0.reminderTime == time }) else {
                return false
              }
              Task { await store.setHabitReminderTime(policy: policy, to: time, in: policies) }
              return true
            },
            turnOn: { Task { await store.toggleHabitReminderEnabled(policy: policy) } },
            remove: { Task { await store.removeHabitReminder(habitID: habit.id, policyID: policy.id) } }
          )
        }
      }
      Divider()
    }
    addButton
  }

  /// Adds a reminder at the next free time; its icon sits in the rows' bell
  /// column, so the editor reads as one list.
  private var addButton: some View {
    Button {
      let clock = HabitReminderTime.nextFreeClock(after: policies.map(\.reminderTime))
      Task { await store.addHabitReminder(habitID: habit.id, time: clock) }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "plus.circle.fill")
          .frame(width: HabitReminderTimeRow.iconWidth)
        Text(String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle))
      }
      .foregroundStyle(LorvexDesign.Palette.accent)
      .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .font(LorvexDesign.Typography.primaryText)
    .padding(.top, policies.isEmpty ? 0 : LorvexDesign.Spacing.xs)
    .accessibilityIdentifier("habit.reminders.add")
  }
}

/// One reminder in the editor: a bell, its time in a clock field, Turn On
/// while it is switched off, and a remove button.
///
/// The row edits a local copy of the time and hands it to `retime` once the
/// field has rested for 0.8 seconds, or when the row goes away with an edit
/// still unsaved, so stepping through the hours saves once. `retime` returns
/// false for a time another reminder already holds; the field then returns
/// to the stored time. A reload that brings a new stored time replaces the
/// local copy.
private struct HabitReminderTimeRow: View {
  /// The bell column's width, which Add Reminder's icon shares.
  static let iconWidth: CGFloat = 18

  let policy: HabitReminderPolicy
  let retime: (String) -> Bool
  let turnOn: () -> Void
  let remove: () -> Void

  @State private var date: Date
  /// The last time handed to `retime`, so a pending save is not repeated.
  @State private var savedClock: String

  init(
    policy: HabitReminderPolicy, retime: @escaping (String) -> Bool,
    turnOn: @escaping () -> Void, remove: @escaping () -> Void
  ) {
    self.policy = policy
    self.retime = retime
    self.turnOn = turnOn
    self.remove = remove
    _date = State(initialValue: HabitReminderTime.date(fromClock: policy.reminderTime))
    _savedClock = State(initialValue: policy.reminderTime)
  }

  private var clock: String { HabitReminderTime.clock(from: date) }
  private var timeLabel: String { HabitReminderTime.display(policy.reminderTime) }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: policy.enabled ? "bell.fill" : "bell.slash")
        .foregroundStyle(policy.enabled ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary))
        .frame(width: Self.iconWidth)
        .accessibilityHidden(true)
      HabitReminderClockField(
        date: $date,
        label: String(localized: "habit_detail.reminder.time", defaultValue: "Reminder Time", table: "Localizable", bundle: LorvexL10n.bundle))
      Spacer(minLength: 0)
      if !policy.enabled {
        Button(String(localized: "habit_detail.reminder.turn_on", defaultValue: "Turn On", table: "Localizable", bundle: LorvexL10n.bundle), action: turnOn)
          .buttonStyle(.borderless)
          .accessibilityLabel(String(
            format: String(localized: "habits.reminders.reenable", defaultValue: "Enable reminder at %@", table: "Localizable", bundle: LorvexL10n.bundle),
            timeLabel))
          .accessibilityIdentifier("habit.reminders.turnOn")
      }
      LorvexIconButton(
        systemImage: "xmark",
        label: String(localized: "habits.reminders.remove", defaultValue: "Remove Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
        accessibilityIdentifier: "habit.reminders.remove",
        action: remove)
    }
    .font(LorvexDesign.Typography.primaryText)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("habit.reminders.row")
    .task(id: clock) {
      guard clock != savedClock else { return }
      try? await Task.sleep(for: .milliseconds(800))
      guard !Task.isCancelled else { return }
      save()
    }
    .onDisappear {
      if clock != savedClock { save() }
    }
    .onChange(of: policy.reminderTime) { _, stored in
      date = HabitReminderTime.date(fromClock: stored)
      savedClock = stored
    }
  }

  private func save() {
    let pending = clock
    if retime(pending) {
      savedClock = pending
    } else {
      date = HabitReminderTime.date(fromClock: policy.reminderTime)
      savedClock = policy.reminderTime
    }
  }
}

/// A reminder's time of day as a system clock field, in the clock the person
/// chose (popover content does not inherit the scene's clock locale). Only
/// the hour and minute of `date` are read and written.
struct HabitReminderClockField: View {
  @Binding var date: Date
  let label: String

  var body: some View {
    DatePicker(label, selection: $date, displayedComponents: .hourAndMinute)
      .datePickerStyle(.field)
      .labelsHidden()
      .fixedSize()
      .lorvexClockLocale()
      .accessibilityLabel(label)
  }
}
