import LorvexCore
import SwiftUI

/// A time-of-day control matching ``LorvexDateChip``'s polish: a chip that reads
/// as the formatted time and opens a popover with a live preview and a custom
/// hour + minute grid (accent-disc selection, in the spirit of
/// ``LorvexMiniMonth``), replacing the stock compact hour/minute `DatePicker` —
/// a crude stepper field. The bound `Date`'s day component is ignored; only the
/// hour and minute are read and written. Hours follow the chosen clock
/// (``LorvexClockFormat``, by default the locale's 12-/24-hour convention) (a 12-hour locale gets an AM/PM segment using the locale symbols).
///
/// A chip given an ``allowedRange`` offers only the times inside it: an hour
/// with no allowed minute and a minute outside the range are dimmed and
/// inert, and any other change that would leave the range (the AM/PM switch)
/// lands on the nearest allowed time. Without a range every time is offered.
struct LorvexTimeChip: View {
  @Environment(\.timeZone) private var timeZone

  let date: Date
  var accessibilityIdentifier: String = "lorvex.timeChip"
  /// What the time is ("Start"), when the chip sits beside another chip and
  /// VoiceOver needs the name before the time; nil reads the time alone.
  var accessibilityName: String?
  /// The times that may be chosen, compared by hour and minute on the day of
  /// ``date``; a bound on an earlier or later day clips to that day's edge.
  /// nil allows every time.
  var allowedRange: ClosedRange<Date>?
  let onSet: (Date) -> Void

  @State private var isPresented = false

  private var timeText: String {
    TaskReminderDateTime.displayTimeString(from: date, timeZone: timeZone)
  }

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "clock")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.tint)
        Text(timeText)
          .font(LorvexDesign.Typography.primaryText)
          .monospacedDigit()
          .foregroundStyle(.primary)
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(.quaternary.opacity(0.55), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityName ?? timeText)
    .accessibilityValue(accessibilityName == nil ? "" : timeText)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier(accessibilityIdentifier)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      LorvexTimeChipPopover(date: date, allowedRange: allowedRange, onSet: onSet)
        .environment(\.timeZone, timeZone)
    }
  }
}

struct LorvexTimeChipPopover: View {
  @Environment(\.timeZone) private var timeZone

  let date: Date
  var allowedRange: ClosedRange<Date>?
  let onSet: (Date) -> Void

  private static let cellSize: CGFloat = 34

  private var calendar: Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
  }

  /// The allowed minutes of the day, or nil when every time is allowed.
  private var allowedMinutes: ClosedRange<Int>? {
    Self.allowedMinutes(for: allowedRange, on: date, calendar: calendar)
  }

  private var currentHour: Int { calendar.component(.hour, from: date) }
  private var currentMinute: Int { calendar.component(.minute, from: date) }
  private var isPM: Bool { currentHour >= 12 }

  /// Whether the clock the user chose (``LorvexClockFormat``, by default the
  /// locale's) formats hours without an AM/PM marker.
  private var uses24Hour: Bool {
    let template =
      DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: LorvexClockFormat.displayLocale)
      ?? "HH"
    return !template.contains("a")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      // Live preview of the chosen time.
      Text(TaskReminderDateTime.displayTimeString(from: date, timeZone: timeZone))
        .font(LorvexDesign.Typography.sectionHeader)
        .monospacedDigit()
        .foregroundStyle(.tint)

      hourGrid

      if !uses24Hour {
        Picker("", selection: meridiemBinding) {
          Text(Self.amSymbol).tag(false)
          Text(Self.pmSymbol).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("lorvex.timeChip.meridiem")
      }

      Divider()

      minuteGrid
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 280)
    .accessibilityIdentifier("lorvex.timeChip.popover")
  }

  // MARK: Hours

  private var hourValues: [Int] { uses24Hour ? Array(0...23) : Array(1...12) }

  private var hourGrid: some View {
    grid {
      ForEach(hourValues, id: \.self) { value in
        cell(
          label: uses24Hour
            ? value.formatted(.number.precision(.integerLength(2))) : value.formatted(),
          selected: isHourSelected(value),
          isEnabled: hasAllowedMinute(inHour: hour24(forDisplay: value))
        ) {
          commit(hour: hour24(forDisplay: value), minute: currentMinute)
        }
      }
    }
  }

  private func isHourSelected(_ displayHour: Int) -> Bool {
    guard !uses24Hour else { return displayHour == currentHour }
    let current12 = currentHour % 12 == 0 ? 12 : currentHour % 12
    return displayHour == current12
  }

  /// Map a displayed hour (1...12 with the current AM/PM, or 0...23) to a
  /// 24-hour value.
  private func hour24(forDisplay displayHour: Int) -> Int {
    guard !uses24Hour else { return displayHour }
    return (displayHour % 12) + (isPM ? 12 : 0)
  }

  private var meridiemBinding: Binding<Bool> {
    Binding(
      get: { isPM },
      set: { pm in commit(hour: (currentHour % 12) + (pm ? 12 : 0), minute: currentMinute) }
    )
  }

  // MARK: Minutes (5-minute steps)

  private var minuteGrid: some View {
    grid {
      ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
        cell(
          label: ":" + value.formatted(.number.precision(.integerLength(2))),
          selected: value == currentMinute,
          isEnabled: isAllowed(hour: currentHour, minute: value)
        ) {
          commit(hour: currentHour, minute: value)
        }
      }
    }
  }

  // MARK: Allowed range

  /// The minutes of the day (0...1439) that `range` allows on the day of
  /// `date`, or nil when there is no range or it leaves no time of that day.
  static func allowedMinutes(
    for range: ClosedRange<Date>?, on date: Date, calendar: Calendar
  ) -> ClosedRange<Int>? {
    guard let range else { return nil }
    func minuteOfDay(_ bound: Date) -> Int {
      let parts = calendar.dateComponents([.hour, .minute], from: bound)
      let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
      if calendar.isDate(bound, inSameDayAs: date) { return minutes }
      return bound < date ? -1 : 1440 + minutes
    }
    let lower = max(0, minuteOfDay(range.lowerBound))
    let upper = min(1439, minuteOfDay(range.upperBound))
    return lower <= upper ? lower...upper : nil
  }

  /// The allowed minute of the day nearest to `candidate`.
  static func clamped(_ candidate: Int, to allowed: ClosedRange<Int>?) -> Int {
    guard let allowed else { return candidate }
    return min(max(candidate, allowed.lowerBound), allowed.upperBound)
  }

  private func isAllowed(hour: Int, minute: Int) -> Bool {
    allowedMinutes?.contains(hour * 60 + minute) ?? true
  }

  private func hasAllowedMinute(inHour hour: Int) -> Bool {
    allowedMinutes?.overlaps(hour * 60...(hour * 60 + 59)) ?? true
  }

  // MARK: Shared cell + grid (accent disc when selected, like LorvexMiniMonth)

  private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(Self.cellSize), spacing: 2), count: 6),
      spacing: 2,
      content: content
    )
  }

  private func cell(
    label: String, selected: Bool, isEnabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(label)
        .font(LorvexDesign.Typography.secondaryText.weight(selected ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .frame(width: Self.cellSize, height: 30)
        .background {
          if selected {
            Circle().fill(Color.accentColor).frame(width: 30, height: 30)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }

  private func commit(hour: Int, minute: Int) {
    let target = Self.clamped(hour * 60 + minute, to: allowedMinutes)
    let updated =
      calendar.date(bySettingHour: target / 60, minute: target % 60, second: 0, of: date) ?? date
    onSet(updated)
  }

  private static let amSymbol: String = DateFormatter().amSymbol ?? "AM"
  private static let pmSymbol: String = DateFormatter().pmSymbol ?? "PM"
}
