import LorvexCore
import SwiftUI

/// The habit inspector's History panel: the habit's check-ins over the past
/// year as a grid of days, a week to a column from Monday to Sunday, the
/// newest week last.
///
/// The grid spans the panel: it shows as many of the newest weeks as the
/// width holds and grows the cells to fill it (``HabitHistoryGridLayout``).
/// Weeks are Monday to Sunday, the week the habit's own progress counts, so a
/// column of a weekly habit is one of its periods. A cell's fill is how far
/// the day went toward the per-day target on a five-step ramp of the habit's
/// color (``HabitHeatmapModel/level(value:target:)``), from a neutral wash
/// for no check-in to the full color for the target met. A habit on chosen
/// weekdays draws its other days fainter, so its pattern shows. Today has an
/// outline, and every day names its date and count in a help tag. With
/// Differentiate Without Color on, a slash marks a partial day and a dot a
/// met one.
///
/// A habit counted several times a day explains its ramp with a "Less…More"
/// legend; a habit done once a day has only the two ends, which need none.
/// The grid waits for the inspector's detail behind a placeholder laid out
/// like it, so the panel keeps its height when the detail arrives.
struct HabitHistoryPanel: View {
  let habit: LorvexHabit
  let detail: AppStore.HabitDetail?
  /// The product time zone, which the completion keys are written in and
  /// which places today's cell.
  let timeZone: TimeZone

  @State private var cache: HistoryCache
  @ScaledMetric(relativeTo: .caption) private var weekdayLabelWidth: CGFloat = 12
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

  /// The weeks the grid holds; the layout shows the newest that fit.
  static let weeks = 53

  /// The grid's calendar: Gregorian in `timeZone`, with ISO weeks (Monday
  /// first), the weeks ``HabitPeriodProgress`` counts.
  private static func calendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  init(habit: LorvexHabit, detail: AppStore.HabitDetail?, timeZone: TimeZone) {
    self.habit = habit
    self.detail = detail
    self.timeZone = timeZone
    _cache = State(
      initialValue: Self.makeCache(habit: habit, detail: detail, calendar: Self.calendar(timeZone)))
  }

  private var identity: Color { LorvexHabitPalette.baseColor(for: habit) }

  var body: some View {
    InspectorPanel(accessibilityIdentifier: "habit.detail.history.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "habit_detail.history.title", defaultValue: "History", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "calendar"
          )
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
          Spacer(minLength: LorvexDesign.Spacing.s)
          if habit.targetCount > 1 {
            legend
          }
        }

        if detail != nil {
          grid
          if detail?.completions.completions.isEmpty == true {
            Text(LocalizedStringResource("habit_detail.history.empty", defaultValue: "No check-ins yet", table: "Localizable", bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
          }
        } else {
          placeholder
        }
      }
    }
    .onChange(of: detail) { _, _ in refreshCache() }
    .onChange(of: habit.targetCount) { _, _ in refreshCache() }
    .onChange(of: habit.weekdays) { _, _ in refreshCache() }
    .onChange(of: timeZone) { _, _ in refreshCache() }
  }

  // MARK: Grid

  private var grid: some View {
    HabitHistoryGridLayout(labelWidth: weekdayLabelWidth) {
      weekdayColumn
      ForEach(Array(cache.grid.columns.enumerated()), id: \.offset) { index, column in
        weekColumn(
          column, monthLabel: cache.grid.monthLabels[index],
          isNewest: index == cache.grid.columns.count - 1)
      }
    }
    .tint(identity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
    .accessibilityIdentifier("habit.detail.history.grid")
  }

  /// The grid's footprint while the detail loads: the same layout over empty
  /// weeks, so it takes the height the grid will.
  private var placeholder: some View {
    HabitHistoryGridLayout(labelWidth: weekdayLabelWidth) {
      Color.clear
      ForEach(0..<Self.weeks, id: \.self) { _ in Color.clear }
    }
    .background(
      .quaternary.opacity(0.4),
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
    )
    .accessibilityElement()
    .accessibilityLabel(String(localized: "habits.heatmap.loading_a11y", defaultValue: "Loading habit history", table: "Localizable", bundle: LorvexL10n.bundle))
  }

  /// The weekday initials beside the rows, on every other row (Monday,
  /// Wednesday, Friday, Sunday). Each keeps its text size and centers on its
  /// row, overhanging the empty rows beside it rather than shrinking to a
  /// row's height.
  private var weekdayColumn: some View {
    VStack(alignment: .leading, spacing: HabitHistoryGridLayout.spacing) {
      Color.clear.frame(height: HabitHistoryGridLayout.monthRowHeight)
      ForEach(Array(HabitHeatmapModel.weekdayInitials(calendar: Self.calendar(timeZone)).enumerated()), id: \.offset) {
        index, symbol in
        Text(verbatim: index.isMultiple(of: 2) ? symbol : "")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize()
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
      }
    }
  }

  /// One week: its month's name where a month begins, over the seven days.
  /// The name runs on past the column over the weeks after it, or, in the
  /// newest week, back over the weeks before, so it ends at the grid's edge.
  private func weekColumn(_ column: [HabitHeatmapModel.Cell], monthLabel: String?, isNewest: Bool)
    -> some View
  {
    VStack(spacing: HabitHistoryGridLayout.spacing) {
      Color.clear
        .frame(height: HabitHistoryGridLayout.monthRowHeight)
        .overlay(alignment: isNewest ? .trailing : .leading) {
          if let monthLabel {
            Text(monthLabel)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .fixedSize()
          }
        }
      ForEach(Array(column.enumerated()), id: \.element.slot) { row, cell in
        cellView(cell, row: row)
      }
    }
  }

  @ViewBuilder
  private func cellView(_ cell: HabitHeatmapModel.Cell, row: Int) -> some View {
    let shape = RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
    if cell.intensity == .absent {
      Color.clear.aspectRatio(1, contentMode: .fit)
    } else {
      shape
        .fill(fill(for: cell, row: row))
        .overlay {
          if differentiateWithoutColor {
            intensityMark(cell.intensity)
          }
        }
        .overlay {
          if cell.date == cache.todayKey {
            shape.strokeBorder(Color.primary.opacity(0.55), lineWidth: 1)
          }
        }
        .aspectRatio(1, contentMode: .fit)
        .help(cache.help[cell.slot] ?? "")
    }
  }

  /// With Differentiate Without Color on, a mark that tells the states apart
  /// without the ramp: a slash for part of the target, a dot for the target
  /// met.
  @ViewBuilder
  private func intensityMark(_ intensity: HabitHeatmapModel.Intensity) -> some View {
    switch intensity {
    case .partial:
      Capsule()
        .fill(.primary.opacity(0.4))
        .frame(height: 1.5)
        .scaleEffect(x: 0.5, y: 1)
        .rotationEffect(.degrees(-45))
    case .met:
      Circle()
        .fill(.primary.opacity(0.3))
        .scaleEffect(0.42)
    default:
      EmptyView()
    }
  }

  private func fill(for cell: HabitHeatmapModel.Cell, row: Int) -> AnyShapeStyle {
    if cell.level == 0, let scheduled = cache.scheduledRows, !scheduled.contains(row) {
      return AnyShapeStyle(.quaternary.opacity(0.4))
    }
    return Self.fill(forLevel: cell.level)
  }

  /// The ramp: a neutral wash for no check-in, then four steps of `.tint`
  /// (the habit's color) to the full color for the target met, correct in
  /// light and dark without fixed shades.
  private static func fill(forLevel level: Int) -> AnyShapeStyle {
    switch level {
    case ...0: AnyShapeStyle(.quaternary)
    case 1: AnyShapeStyle(.tint.opacity(0.28))
    case 2: AnyShapeStyle(.tint.opacity(0.5))
    case 3: AnyShapeStyle(.tint.opacity(0.72))
    default: AnyShapeStyle(.tint)
    }
  }

  private var legend: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Text(LocalizedStringResource("habits.heatmap.legend.less", defaultValue: "Less", table: "Localizable", bundle: LorvexL10n.bundle))
      ForEach(0...4, id: \.self) { level in
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(Self.fill(forLevel: level))
          .frame(width: HabitHistoryGridLayout.minimumCell, height: HabitHistoryGridLayout.minimumCell)
      }
      Text(LocalizedStringResource("habits.heatmap.legend.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .fixedSize()
    .tint(identity)
    .accessibilityHidden(true)
  }

  private var accessibilitySummary: String {
    let cells = cache.grid.columns.joined()
    let weeks = cache.grid.columns.count
    let metDays = cells.filter { $0.intensity == .met }.count
    let partialDays = cells.filter { $0.intensity == .partial }.count
    return String(
      localized: "habits.heatmap.summary_a11y",
      defaultValue:
        "Completion heatmap for the last \(weeks) weeks: \(metDays) days met target, \(partialDays) partial days",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  // MARK: Cache

  /// The grid and what its cells draw, built once per change to the history
  /// rather than on every pass through `body`.
  private struct HistoryCache {
    var grid: HabitHeatmapModel.Grid
    /// Each cell's help tag by slot: its date and count.
    var help: [Int: String]
    /// The rows of the weekdays a habit on chosen weekdays is planned on
    /// (0 = Monday); nil when every day is planned.
    var scheduledRows: Set<Int>?
    var todayKey: String
  }

  private func refreshCache() {
    cache = Self.makeCache(habit: habit, detail: detail, calendar: Self.calendar(timeZone))
  }

  private static func makeCache(
    habit: LorvexHabit, detail: AppStore.HabitDetail?, calendar: Calendar
  ) -> HistoryCache {
    let now = Date()
    let todayKey = dayKey(now, calendar)
    guard let detail else {
      return HistoryCache(grid: .empty, help: [:], scheduledRows: nil, todayKey: todayKey)
    }
    let grid = HabitHeatmapModel.makeGrid(
      completions: detail.completions.completions,
      targetCount: habit.targetCount,
      weeks: weeks,
      endDate: now,
      calendar: calendar)
    let target = max(habit.targetCount, 1)
    var help: [Int: String] = [:]
    for cell in grid.columns.joined() where cell.intensity != .absent {
      help[cell.slot] = helpText(for: cell, target: target, calendar: calendar)
    }
    var scheduledRows: Set<Int>?
    if habit.frequencyType == "weekly", let days = habit.weekdays, !days.isEmpty, Set(days).count < 7 {
      scheduledRows = Set(days)
    }
    return HistoryCache(grid: grid, help: help, scheduledRows: scheduledRows, todayKey: todayKey)
  }

  /// "Wed, Sep 30 · Done", "Wed, Sep 30 · 3 of 8", or "Wed, Sep 30 · No
  /// check-in".
  private static func helpText(
    for cell: HabitHeatmapModel.Cell, target: Int, calendar: Calendar
  ) -> String {
    var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
    style.timeZone = calendar.timeZone
    let day = date(fromKey: cell.date, calendar).map { $0.formatted(style) } ?? cell.date
    if cell.value <= 0 {
      return String(
        format: String(localized: "habit_detail.history.cell.none", defaultValue: "%@ · No check-in", table: "Localizable", bundle: LorvexL10n.bundle),
        day)
    }
    if target > 1 {
      return String(
        localized: "habit_detail.history.cell.count",
        defaultValue: "\(day) · \(cell.value) of \(target)",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      format: String(localized: "habit_detail.history.cell.done", defaultValue: "%@ · Done", table: "Localizable", bundle: LorvexL10n.bundle),
      day)
  }

  private static func dayKey(_ date: Date, _ calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  private static func date(fromKey key: String, _ calendar: Calendar) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}

/// Lays out the History panel's grid: the weekday initials' column, then the
/// week columns, oldest to newest.
///
/// It shows as many of the newest weeks as the proposed width holds at
/// ``minimumCell`` and grows the cells to fill the width, up to
/// ``maximumCell``, so the grid spans the panel without a ragged edge. Weeks
/// that do not fit are placed far outside the bounds, so what shows always
/// ends on the current week. The count is decided per layout pass rather than
/// measured into view state, which would lag a resize by a frame. Every
/// column is proposed the grid's full height, which its seven square cells
/// and month row fill.
struct HabitHistoryGridLayout: Layout {
  static let minimumCell: CGFloat = 10
  static let maximumCell: CGFloat = 16
  static let spacing: CGFloat = 3
  static let monthRowHeight: CGFloat = 14

  /// The weekday initials' column width.
  let labelWidth: CGFloat

  /// The weeks shown of `count` in `width` and their cell size.
  static func metrics(columns count: Int, width: CGFloat, labelWidth: CGFloat) -> (shown: Int, cell: CGFloat) {
    guard count > 0 else { return (0, minimumCell) }
    let available = max(0, width - labelWidth - spacing)
    let fitted = Int((available + spacing) / (minimumCell + spacing))
    let shown = max(1, min(count, fitted))
    let cell = (available - spacing * CGFloat(shown - 1)) / CGFloat(shown)
    return (shown, min(max(cell, 1), maximumCell))
  }

  /// The grid's height at a cell size: the month row and seven rows of cells.
  static func height(cell: CGFloat) -> CGFloat {
    monthRowHeight + spacing + 7 * cell + 6 * spacing
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let count = max(subviews.count - 1, 0)
    guard let width = proposal.width, width.isFinite else {
      let width = labelWidth + Self.spacing + CGFloat(count) * (Self.minimumCell + Self.spacing) - Self.spacing
      return CGSize(width: max(width, 0), height: Self.height(cell: Self.minimumCell))
    }
    let metrics = Self.metrics(columns: count, width: width, labelWidth: labelWidth)
    return CGSize(width: width, height: Self.height(cell: metrics.cell))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let labels = subviews.first else { return }
    let count = subviews.count - 1
    let metrics = Self.metrics(columns: count, width: bounds.width, labelWidth: labelWidth)
    let height = Self.height(cell: metrics.cell)
    labels.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: labelWidth, height: height))
    let hidden = count - metrics.shown
    let gridMinX = bounds.minX + labelWidth + Self.spacing
    for (index, subview) in subviews.dropFirst().enumerated() {
      let column = index - hidden
      let x = column < 0 ? bounds.minX - 100_000 : gridMinX + CGFloat(column) * (metrics.cell + Self.spacing)
      subview.place(
        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: metrics.cell, height: height))
    }
  }
}
