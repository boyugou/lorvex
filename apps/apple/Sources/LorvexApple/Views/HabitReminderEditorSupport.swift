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

/// Conversions between the stored "HH:mm" reminder strings and the `Date`s
/// the reminder time controls read and write, plus the "throughout the day"
/// spacing math. Times are minutes-of-day on an arbitrary reference day; only the hour
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

  /// Locale-formatted display for an "HH:mm" slot ("9:00 AM", or "09:00" on a
  /// 24-hour clock).
  static func display(_ clock: String) -> String {
    lorvexClockTimeLabel(clock)
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

  /// The "HH:mm" time a newly added reminder takes: an hour after the latest
  /// of `times` (9:00 when there are none), wrapping within the day, moved on
  /// an hour at a time past any time already taken, and five minutes at a
  /// time once every such hour is. Never one of `times` unless all 288
  /// five-minute slots of the day are.
  static func nextFreeClock(after times: [String]) -> String {
    let taken = Set(times.compactMap(minutesOfDay))
    let day = 24 * 60
    let start = taken.max().map { ($0 + 60) % day } ?? 9 * 60
    for step in [60, 5] {
      for index in 0..<(day / step) {
        let minutes = (start + index * step) % day
        if !taken.contains(minutes) { return clock(from: date(fromMinutes: minutes)) }
      }
    }
    return clock(from: date(fromMinutes: start))
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
        localized: "habits.reminders.hint.times_per_week",
        defaultValue: "Nudges on days you’re behind, until you’ve logged \(n) this week.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "monthly":
      let day = habit.dayOfMonth ?? 1
      return String(
        localized: "habits.reminders.hint.monthly",
        defaultValue: "Reminds on day \(day) each month, and stops once it’s done.",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case "daily", "weekly":
      if habit.targetCount > 1 {
        return String(
          localized: "habits.reminders.hint.multi",
          defaultValue: "Stops once you log \(habit.targetCount) today.",
          table: "Localizable", bundle: LorvexL10n.bundle)
      }
      return String(
        localized: "habits.reminders.hint.daily",
        defaultValue: "Only on the days this habit is scheduled, and stops once it’s done.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    default:
      return nil
    }
  }
}

/// The "throughout the day" window for a multi-count habit: a start and an
/// end time in clock fields, a line saying how many reminders the window
/// makes and how far apart, and a button that replaces the habit's reminders
/// with those evenly spaced times.
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
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "clock")
          .foregroundStyle(.secondary)
          .frame(width: 18)
          .accessibilityHidden(true)
        HabitReminderClockField(
          date: $windowStart,
          label: String(localized: "habits.reminders.window.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("habit.reminders.window.start")
        Text(verbatim: "–").foregroundStyle(.secondary)
        HabitReminderClockField(
          date: $windowEnd,
          label: String(localized: "habits.reminders.window.end", defaultValue: "End", table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("habit.reminders.window.end")
      }
      .font(LorvexDesign.Typography.primaryText)

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
          String(localized: "habits.reminders.window.apply", defaultValue: "Set These Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "bell.badge")
      }
      .buttonStyle(.bordered)
      .disabled(endMinutes <= startMinutes)
      .accessibilityIdentifier("habit.reminders.window.apply")
    }
  }

  private var previewText: String {
    let count = habit.targetCount
    let interval = LorvexDurationFormat.hoursAndMinutes(
      HabitReminderTime.intervalMinutes(start: startMinutes, end: endMinutes, count: count))
    return String(
      localized: "habits.reminders.window.preview",
      defaultValue: "\(count) reminders · about every \(interval) · stops once you log \(count) today",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

}
