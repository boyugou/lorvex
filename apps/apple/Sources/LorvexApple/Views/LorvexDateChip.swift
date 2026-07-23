import LorvexCore
import SwiftUI

/// A date control with the texture of a peer task manager, replacing the
/// stock compact `DatePicker` (stepper field + dated popup): the value reads
/// as a calendar chip, and clicking it opens a popover with quick actions
/// (Today / Tomorrow / Next Week), a custom ``LorvexMiniMonth`` grid, an
/// optional time row, and — when a value is set and the field is clearable — a
/// Clear action. `nil` renders the placeholder as a ghost chip, so set/unset
/// needs no separate checkbox.
struct LorvexDateChip: View {
  @Environment(\.timeZone) private var timeZone

  /// Current value; `nil` renders the placeholder chip.
  let date: Date?
  /// Chip label while no date is set, e.g. "Set Date".
  let placeholder: String
  /// Overrides the chip's text while keeping the day-picker popover. Used by the
  /// week navigator to display a range (e.g. "Jun 14 – Jun 20") on the same chip
  /// that picks a single day — picking any day jumps to the week containing it.
  var displayTextOverride: String? = nil
  /// Include the time-of-day field in the popover's picker (reminders).
  var includesTime = false
  /// Earliest selectable instant (reminders refuse the past).
  var minDate: Date? = nil
  /// Nil hides the Clear action (the field is required once set).
  var onClear: (() -> Void)? = nil
  let onSet: (Date) -> Void

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: includesTime ? "bell" : "calendar")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(date == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        Text(chipTitle)
          .font(LorvexDesign.Typography.primaryText)
          .lineLimit(1)
          .foregroundStyle(date == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      }
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(.quaternary.opacity(date == nil ? 0.35 : 0.55), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(chipTitle)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("lorvex.dateChip")
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      LorvexDateChipPopover(
        date: date,
        includesTime: includesTime,
        minDate: minDate,
        onClear: onClear.map { clear in
          {
            clear()
            isPresented = false
          }
        },
        onSet: { value in
          onSet(value)
          // Picking a calendar day is a complete answer; a time edit usually
          // continues (date first, then the clock), so keep that one open.
          if !includesTime { isPresented = false }
        }
      )
      .environment(\.timeZone, timeZone)
    }
  }

  private var chipTitle: String {
    if let displayTextOverride { return displayTextOverride }
    guard let date else { return placeholder }
    var style = Date.FormatStyle(
      date: .abbreviated,
      time: includesTime ? .shortened : .omitted
    )
    style.calendar = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
    style.timeZone = timeZone
    return style.format(date)
  }
}

private struct LorvexDateChipPopover: View {
  @Environment(\.timeZone) private var timeZone

  let date: Date?
  let includesTime: Bool
  let minDate: Date?
  let onClear: (() -> Void)?
  let onSet: (Date) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        quickAction(
          String(localized: "date_chip.today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle),
          dayOffset: 0)
        quickAction(
          String(localized: "date_chip.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: LorvexL10n.bundle),
          dayOffset: 1)
        quickAction(
          String(localized: "date_chip.next_week", defaultValue: "Next Week", table: "Localizable", bundle: LorvexL10n.bundle),
          dayOffset: 7)
      }

      LorvexMiniMonth(
        selectedDay: date ?? defaultSelection,
        minDate: minDate
      ) { day in
        onSet(combine(day: day))
      }

      if includesTime {
        Divider()
        HStack {
          Label(
            String(localized: "date_chip.time", defaultValue: "Time", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "clock")
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
          Spacer()
          LorvexTimeChip(
            date: date ?? defaultSelection,
            onSet: { onSet(max($0, minDate ?? .distantPast)) }
          )
          .environment(\.timeZone, timeZone)
        }
        .accessibilityIdentifier("lorvex.dateChip.time")
      }

      if let onClear, date != nil {
        Divider()
        Button(role: .destructive, action: onClear) {
          Label(
            String(localized: "date_chip.clear", defaultValue: "Clear Date", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "xmark.circle"
          )
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .accessibilityIdentifier("lorvex.dateChip.clear")
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 268)
  }

  private var defaultSelection: Date {
    if let minDate, minDate > Date() { return minDate }
    return Date()
  }

  /// Fold a chosen calendar day into the value to commit: a date-only field
  /// takes the day verbatim; a timed field keeps the existing (or default)
  /// time-of-day and clamps to `minDate`.
  private func combine(day: Date) -> Date {
    let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
    guard includesTime else { return day }
    let reference = date ?? defaultSelection
    let time = calendar.dateComponents([.hour, .minute], from: reference)
    let combined = calendar.date(
      bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
    return max(combined, minDate ?? .distantPast)
  }

  private func quickAction(_ title: String, dayOffset: Int) -> some View {
    Button(title) {
      let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
      let day = calendar.date(
        byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date())) ?? Date()
      onSet(combine(day: day))
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }
}

/// A compact, custom month grid in the spirit of Apple Calendar's mini-month —
/// quiet weekday header, muted out-of-month days, today as an accent numeral,
/// the selected day as a filled accent disc. Replaces the stock graphical
/// `DatePicker`, which reads as a generic system control in a calendar context.
private struct LorvexMiniMonth: View {
  @Environment(\.timeZone) private var timeZone

  let selectedDay: Date
  let minDate: Date?
  let onPick: (Date) -> Void

  @State private var visibleMonth: Date

  init(selectedDay: Date, minDate: Date?, onPick: @escaping (Date) -> Void) {
    self.selectedDay = selectedDay
    self.minDate = minDate
    self.onPick = onPick
    _visibleMonth = State(initialValue: Self.startOfMonth(selectedDay))
  }

  private static let cellSize: CGFloat = 34

  private var calendar: Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
  }

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      header
      weekdayHeader
      grid
    }
    .accessibilityIdentifier("lorvex.miniMonth")
    .onAppear {
      let productMonth = Self.startOfMonth(selectedDay, calendar: calendar)
      if visibleMonth != productMonth { visibleMonth = productMonth }
    }
    // `visibleMonth` seeds from `selectedDay` once at init, but the bound day can
    // change externally (a different date picked elsewhere, or a programmatic set)
    // while this grid is on screen. Without this resync the grid would keep showing
    // the month it opened on, hiding the newly-selected day. Only jump when the
    // month actually differs so in-month reselection and manual browsing are kept.
    .onChange(of: selectedDay) { _, newDay in
      let newMonth = Self.startOfMonth(newDay, calendar: calendar)
      if visibleMonth != newMonth { visibleMonth = newMonth }
    }
  }

  private var header: some View {
    HStack(spacing: 0) {
      Text(monthTitle)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(.primary)
      Spacer(minLength: LorvexDesign.Spacing.s)
      monthButton(systemImage: "chevron.left", delta: -1, label: String(
        localized: "mini_month.previous", defaultValue: "Previous month",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
      monthButton(systemImage: "circle.fill", delta: nil, label: String(
        localized: "mini_month.this_month", defaultValue: "Current month",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
        .font(.system(size: 7))
      monthButton(systemImage: "chevron.right", delta: 1, label: String(
        localized: "mini_month.next", defaultValue: "Next month",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
    }
  }

  private func monthButton(systemImage: String, delta: Int?, label: String) -> some View {
    Button {
      if let delta {
        visibleMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
      } else {
        visibleMonth = Self.startOfMonth(Date())
      }
    } label: {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
        Text(symbol)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: Self.cellSize, height: 18)
      }
    }
  }

  private var grid: some View {
    let days = monthDays()
    return LazyVGrid(
      columns: Array(repeating: GridItem(.fixed(Self.cellSize), spacing: 0), count: 7),
      spacing: 2
    ) {
      ForEach(days, id: \.self) { day in
        dayCell(day)
      }
    }
  }

  @ViewBuilder
  private func dayCell(_ day: Date) -> some View {
    let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
    let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
    let isToday = calendar.isDateInToday(day)
    let disabled = minDate.map { calendar.startOfDay(for: day) < calendar.startOfDay(for: $0) } ?? false
    Button {
      onPick(calendar.startOfDay(for: day))
    } label: {
      Text("\(calendar.component(.day, from: day))")
        .font(LorvexDesign.Typography.secondaryText.weight(isSelected || isToday ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(dayForeground(inMonth: inMonth, isSelected: isSelected, isToday: isToday, disabled: disabled))
        .frame(width: Self.cellSize, height: 30)
        .background {
          if isSelected {
            Circle().fill(Color.accentColor).frame(width: 28, height: 28)
          } else if isToday {
            Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 28, height: 28)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel(accessibilityLabel(for: day))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private func dayForeground(
    inMonth: Bool, isSelected: Bool, isToday: Bool, disabled: Bool
  ) -> AnyShapeStyle {
    if isSelected { return AnyShapeStyle(.white) }
    if disabled { return AnyShapeStyle(.tertiary) }
    if isToday { return AnyShapeStyle(Color.accentColor) }
    return inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
  }

  /// 42 days (6 weeks) starting on the locale's first weekday on/before the 1st,
  /// so the grid always has a stable shape regardless of month length.
  private func monthDays() -> [Date] {
    guard
      let firstOfMonth = calendar.date(
        from: calendar.dateComponents([.year, .month], from: visibleMonth))
    else { return [] }
    let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
    let lead = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
    guard let start = calendar.date(byAdding: .day, value: -lead, to: firstOfMonth) else { return [] }
    return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  private var weekdaySymbols: [String] {
    let symbols = calendar.veryShortWeekdaySymbols
    let offset = calendar.firstWeekday - 1
    return Array(symbols[offset...] + symbols[..<offset])
  }

  private static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
    return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
  }

  private var monthTitle: String {
    var style = Date.FormatStyle().year().month(.wide)
    style.calendar = calendar
    style.timeZone = timeZone
    return style.format(visibleMonth)
  }

  private func accessibilityLabel(for day: Date) -> String {
    var style = Date.FormatStyle(date: .complete, time: .omitted)
    style.calendar = calendar
    style.timeZone = timeZone
    return style.format(day)
  }
}
