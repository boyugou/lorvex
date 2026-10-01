import LorvexCore
import SwiftUI

/// Inline composer for a new checklist item. It replaces the "Add Checklist
/// Item" row, takes keyboard focus on appear, and stays open after each added
/// item so several can be typed in a row. It asks the host to dismiss it when
/// focus leaves with nothing typed: a tap elsewhere, a scroll that hides the
/// keyboard, or Return on an empty field.
struct MobileChecklistComposerRow: View {
  let addChecklistItem: (String) async -> Void
  let dismiss: () -> Void

  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack {
      Image(systemName: "circle")
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(.tertiary)
      TextField(
        String(
          localized: "checklist.add_placeholder", defaultValue: "Add checklist item",
          table: "Localizable", bundle: MobileL10n.bundle), text: $text
      )
      .focused($isFocused)
      .submitLabel(.done)
      .onSubmit(submit)
      .accessibilityIdentifier("task.detail.checklist.composer")
      Button(action: submit) {
        Label(
          String(
            localized: "common.add", defaultValue: "Add", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle.fill")
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .disabled(trimmedText.isEmpty)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .onAppear { isFocused = true }
    .onChange(of: isFocused) { _, focused in
      if !focused, trimmedText.isEmpty {
        dismiss()
      }
    }
  }

  private var trimmedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func submit() {
    let trimmed = trimmedText
    guard !trimmed.isEmpty else {
      dismiss()
      return
    }
    text = ""
    Task { await addChecklistItem(trimmed) }
    isFocused = true
  }
}

/// Composes a new reminder for a task, in place of the "Add Reminder" row, as
/// rows of the Reminders section: one row per quick preset that is still
/// ahead, naming it and showing when it rings ("Tomorrow morning … Fri
/// 09:00"), which adds the reminder in one tap; then an "Other Time" row with
/// a date-and-time picker and an add button. The host's section header
/// carries Cancel. Every path hands `addReminder` a single `Date`, then asks
/// the host to dismiss the composer.
///
/// "In an hour" is an absolute elapsed-time preset. Evening and tomorrow are
/// wall-clock presets in Lorvex's synced product timezone, so travel or a
/// device-zone mismatch never changes the time another device will display.
/// A task deadline is a civil `YYYY-MM-DD` with no due-time component, so a
/// "before due" preset would invent an instant and is intentionally absent.
struct MobileReminderComposerRow: View {
  let timeZone: TimeZone
  let dismiss: () -> Void
  let addReminder: (Date) async -> Void

  @State private var date: Date

  init(
    timeZone: TimeZone,
    dismiss: @escaping () -> Void,
    addReminder: @escaping (Date) async -> Void
  ) {
    self.timeZone = timeZone
    self.dismiss = dismiss
    self.addReminder = addReminder
    _date = State(initialValue: TaskReminderDateTime.defaultDate(timeZone: timeZone))
  }

  private enum ReminderPreset: Identifiable {
    case inOneHour
    case thisEvening
    case tomorrowMorning

    var id: Self { self }

    var title: String {
      switch self {
      case .inOneHour:
        return String(
          localized: "reminder.preset.in_1_hour", defaultValue: "In an hour", table: "Localizable",
          bundle: MobileL10n.bundle)
      case .thisEvening:
        return String(
          localized: "reminder.preset.this_evening", defaultValue: "This evening",
          table: "Localizable", bundle: MobileL10n.bundle)
      case .tomorrowMorning:
        return String(
          localized: "reminder.preset.tomorrow_morning", defaultValue: "Tomorrow morning",
          table: "Localizable", bundle: MobileL10n.bundle)
      }
    }

    var systemImage: String {
      switch self {
      case .inOneHour: return "clock"
      case .thisEvening: return "sunset"
      case .tomorrowMorning: return "sunrise"
      }
    }
  }

  var body: some View {
    ForEach(availablePresets(now: LorvexPreviewClock.now(in: .current)), id: \.preset.id) { entry in
      Button {
        add(entry.date)
      } label: {
        // An explicit HStack, not a `Label`: a List tints a button's whole
        // label, and the preset reads as a choice with an accent icon, not as
        // a link.
        HStack(spacing: LorvexDesign.Spacing.s) {
          Image(systemName: entry.preset.systemImage)
            .foregroundStyle(LorvexDesign.Palette.accent)
            .frame(minWidth: 28)
          Text(entry.preset.title)
          Spacer(minLength: LorvexDesign.Spacing.s)
          Text(entry.date.formatted(presetTimeStyle))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .contentShape(Rectangle())
      }
      .foregroundStyle(.primary)
      .accessibilityIdentifier("task.detail.reminders.preset.\(entry.preset.id)")
    }

    HStack(spacing: LorvexDesign.Spacing.s) {
      DatePicker(
        String(
          localized: "reminder.other_time", defaultValue: "Other Time", table: "Localizable",
          bundle: MobileL10n.bundle),
        selection: $date,
        displayedComponents: [.date, .hourAndMinute]
      )
      .environment(\.timeZone, timeZone)
      Button {
        add(date)
      } label: {
        Label(
          String(
            localized: "reminder.add", defaultValue: "Add Reminder", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle.fill")
      }
      .labelStyle(.iconOnly)
      .imageScale(.large)
      .buttonStyle(.borderless)
      // A reminder in the past is rejected at arm time (`fireDate > now`) and
      // would otherwise persist as a row that silently never fires. Disable
      // the confirm button until the chosen instant is in the future.
      .disabled(date <= Date())
      .accessibilityIdentifier("task.detail.reminders.confirm")
    }
    .onChange(of: timeZone.identifier) { _, _ in
      date = TaskReminderDateTime.defaultDate(timeZone: timeZone)
    }
  }

  private func add(_ date: Date) {
    Task { await addReminder(date) }
    dismiss()
  }

  /// A preset's ring time: the weekday and the clock ("Fri 09:00"), in the
  /// product timezone and the chosen clock. Every preset falls within a day,
  /// so the weekday says which day without a date.
  private var presetTimeStyle: Date.FormatStyle {
    var style = Date.FormatStyle().weekday(.abbreviated).hour().minute()
    style.timeZone = timeZone
    style.locale = LorvexClockFormat.current.applied(to: MobileL10n.locale)
    return style
  }

  private func availablePresets(now: Date) -> [(preset: ReminderPreset, date: Date)] {
    var entries: [(ReminderPreset, Date)] = []

    if let date = TaskReminderDateTime.presetDate(
      .inOneHour,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.inOneHour, date))
    }

    if let evening = TaskReminderDateTime.presetDate(
      .thisEvening,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.thisEvening, evening))
    }

    if let morning = TaskReminderDateTime.presetDate(
      .tomorrowMorning,
      now: now,
      timeZone: timeZone)
    {
      entries.append((.tomorrowMorning, morning))
    }

    return entries.map { (preset: $0.0, date: $0.1) }
  }
}
