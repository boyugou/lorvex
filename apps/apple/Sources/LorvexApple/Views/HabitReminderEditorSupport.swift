import Foundation
import LorvexCore
import SwiftUI

/// How a multi-count habit's reminders are authored: a hand-picked set of
/// "specific times", or a "throughout the day" window the editor fills with
/// `targetCount` evenly-spaced reminders. A single-count habit only ever uses
/// `.specific`, so this control is hidden for it.
enum HabitReminderMode: CaseIterable {
  case specific
  case window

  var title: String {
    switch self {
    case .specific:
      String(localized: "habits.reminders.mode.specific", defaultValue: "Specific times", table: "Localizable", bundle: LorvexL10n.bundle)
    case .window:
      String(localized: "habits.reminders.mode.window", defaultValue: "Throughout the day", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// Conversions between the stored "HH:mm" reminder strings and the `Date`s the
/// `LorvexTimeChip` picker reads/writes, plus the "throughout the day" spacing
/// math. Times are minutes-of-day on an arbitrary reference day; only the hour
/// and minute matter.
enum HabitReminderTime {
  static var calendar: Calendar { Calendar.current }

  /// A `Date` on the reference day at the `HH:mm` clock string (defaults to noon
  /// on a parse failure, so a malformed slot still yields a usable picker).
  static func date(fromClock clock: String) -> Date {
    let minutes = minutesOfDay(clock) ?? 12 * 60
    return date(fromMinutes: minutes)
  }

  static func date(fromMinutes minutes: Int) -> Date {
    let clamped = max(0, min(minutes, 24 * 60 - 1))
    let base = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
    return calendar.date(byAdding: .minute, value: clamped, to: base) ?? base
  }

  /// The picker `Date`'s hour/minute as a zero-padded "HH:mm" wire string.
  static func clock(from date: Date) -> String {
    let comps = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
  }

  /// Minutes-since-midnight for an "HH:mm" string, or nil if it doesn't parse.
  static func minutesOfDay(_ clock: String) -> Int? {
    let parts = clock.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return h * 60 + m
  }

  /// Locale-formatted display for an "HH:mm" slot (e.g. "9:00 AM").
  static func display(_ clock: String) -> String {
    date(fromClock: clock).formatted(date: .omitted, time: .shortened)
  }

  /// `count` reminder times spread evenly across the window, each rounded to the
  /// nearest 5 minutes (the picker's grain). The spacing is `window / count` so
  /// the first reminder lands one interval after the start and the last on or
  /// before the end — the firing semantics ("about every Xm") match the gap the
  /// preview line names. A non-positive window collapses to the start time.
  static func evenlySpacedTimes(start: Int, end: Int, count: Int) -> [String] {
    guard count > 0 else { return [] }
    let span = end - start
    guard span > 0 else { return [clock(from: date(fromMinutes: start))] }
    let step = Double(span) / Double(count)
    return (1...count).map { index in
      let raw = Double(start) + step * Double(index)
      let rounded = (Int((raw / 5).rounded()) * 5)
      return clock(from: date(fromMinutes: min(rounded, end)))
    }
  }

  /// The even-spacing interval in minutes for `count` reminders across a window.
  static func intervalMinutes(start: Int, end: Int, count: Int) -> Int {
    guard count > 0, end > start else { return 0 }
    return Int((Double(end - start) / Double(count)).rounded())
  }

  /// A sensible default time for a freshly added reminder: an hour after the
  /// latest existing "HH:mm" reminder (wrapping within the day), else 9:00.
  static func suggestedNext(afterTimes times: [String]) -> Date {
    guard let latest = times.compactMap({ minutesOfDay($0) }).max() else {
      return date(fromClock: "09:00")
    }
    return date(fromMinutes: (latest + 60) % (24 * 60))
  }

  /// A sensible default time for a freshly added reminder: an hour after the
  /// latest existing reminder (wrapping within the day), else 9:00.
  static func suggestedNext(after policies: [HabitReminderPolicy]) -> Date {
    suggestedNext(afterTimes: policies.map(\.reminderTime))
  }
}

/// The cadence-aware hint shown under a habit's reminder chips, phrased as the
/// scheduler's intended completion-aware behavior — so the editor always
/// explains, in words, when the reminders will actually fire.
enum HabitReminderHint {
  static func text(for habit: LorvexHabit, mode: HabitReminderMode) -> String? {
    if habit.targetCount > 1 && mode == .window {
      return nil  // The window section shows its own live preview line.
    }
    switch habit.frequencyType {
    case "times_per_week":
      let n = habit.perPeriodTarget ?? habit.targetCount
      return String(
        format: String(
          localized: "habits.reminders.hint.times_per_week",
          defaultValue: "Nudges on days you're behind, until you've logged %lld this week.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        n)
    case "monthly":
      let day = habit.dayOfMonth ?? 1
      return String(
        format: String(
          localized: "habits.reminders.hint.monthly",
          defaultValue: "Reminds on day %lld each month, and stops once it's done.",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        day)
    case "daily", "weekly":
      if habit.targetCount > 1 {
        return String(
          format: String(
            localized: "habits.reminders.hint.multi",
            defaultValue: "Stops once you log %lld today.",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          habit.targetCount)
      }
      return String(
        localized: "habits.reminders.hint.daily",
        defaultValue: "Only on the days this habit is scheduled, and stops once it's done.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    default:
      return nil
    }
  }
}

/// The "throughout the day" window editor for a multi-count habit: a start and
/// end `LorvexTimeChip` plus a live preview of how many reminders the window
/// generates and their spacing. Committing rewrites the habit's whole reminder
/// set to the evenly-spaced times via the store.
struct HabitReminderWindowSection: View {
  @Bindable var store: AppStore
  let habit: LorvexHabit
  @Binding var windowStart: Date
  @Binding var windowEnd: Date

  private var startMinutes: Int { HabitReminderTime.minutesOfDay(HabitReminderTime.clock(from: windowStart)) ?? 540 }
  private var endMinutes: Int { HabitReminderTime.minutesOfDay(HabitReminderTime.clock(from: windowEnd)) ?? 1260 }

  private var generatedTimes: [String] {
    HabitReminderTime.evenlySpacedTimes(
      start: startMinutes, end: endMinutes, count: habit.targetCount)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        labeledChip(
          title: String(localized: "habits.reminders.window.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
          date: $windowStart, identifier: "habit.reminders.window.start")
        Image(systemName: "arrow.right")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.tertiary)
        labeledChip(
          title: String(localized: "habits.reminders.window.end", defaultValue: "End", table: "Localizable", bundle: LorvexL10n.bundle),
          date: $windowEnd, identifier: "habit.reminders.window.end")
      }

      Text(previewText)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("habit.reminders.window.preview")

      Button {
        let times = generatedTimes
        Task { await store.setHabitReminderTimes(habitID: habit.id, times: times) }
      } label: {
        Label(
          String(localized: "habits.reminders.window.apply", defaultValue: "Set these reminders", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "bell.badge")
      }
      .buttonStyle(.lorvexSecondary)
      .disabled(endMinutes <= startMinutes)
      .accessibilityIdentifier("habit.reminders.window.apply")
    }
  }

  private func labeledChip(title: String, date: Binding<Date>, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      LorvexTimeChip(date: date.wrappedValue, accessibilityIdentifier: identifier) {
        date.wrappedValue = $0
      }
    }
  }

  private var previewText: String {
    let count = habit.targetCount
    let interval = HabitReminderTime.intervalMinutes(
      start: startMinutes, end: endMinutes, count: count)
    return String(
      format: String(
        localized: "habits.reminders.window.preview",
        defaultValue: "%lld reminders · about every %@ · stops once you log %lld today",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      count, Self.intervalLabel(minutes: interval), count)
  }

  /// "1h 43m" / "45m" / "2h" for an interval in minutes.
  static func intervalLabel(minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
  }
}

/// The trailing `xmark` chip button that removes a reminder time, shared by the
/// create-draft field and the live detail editor so the two delete affordances
/// stay pixel-identical.
struct HabitReminderDeleteButton: View {
  let onDelete: () -> Void

  var body: some View {
    Button(action: onDelete) {
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
}

/// The "Add reminder" affordance shared by the create-draft field and the live
/// detail editor: a secondary "+" button that swaps to an inline
/// ``LorvexTimeChip`` with confirm/cancel. `idPrefix` namespaces the
/// accessibility identifiers per surface (`habit.reminders` /
/// `createHabit.reminders`); `suggestedTime` seeds the picker when it opens and
/// `onAdd` receives the confirmed "HH:mm" clock string.
struct HabitReminderAddAffordance: View {
  let idPrefix: String
  let suggestedTime: () -> Date
  let onAdd: (String) -> Void

  @State private var draftTime = HabitReminderTime.date(fromClock: "09:00")
  @State private var isAddingTime = false

  var body: some View {
    if isAddingTime {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        LorvexTimeChip(date: draftTime, accessibilityIdentifier: "\(idPrefix).add.timeChip") {
          draftTime = $0
        }
        Button {
          onAdd(HabitReminderTime.clock(from: draftTime))
          isAddingTime = false
        } label: {
          Image(systemName: "checkmark")
        }
        .buttonStyle(.lorvex(.primary))
        .accessibilityLabel(String(
          localized: "habits.reminders.add", defaultValue: "Add Reminder",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("\(idPrefix).add.confirm")
        Button { isAddingTime = false } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.lorvexNeutral)
        .accessibilityLabel(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    } else {
      Button {
        draftTime = suggestedTime()
        isAddingTime = true
      } label: {
        Label(
          String(localized: "habits.reminders.add", defaultValue: "Add Reminder", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus"
        )
      }
      .buttonStyle(.lorvexSecondary)
      .accessibilityIdentifier("\(idPrefix).add")
    }
  }
}
