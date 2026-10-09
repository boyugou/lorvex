import LorvexCore
import SwiftUI

struct MobileHabitVisualizationSection: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail?
  /// The product time zone, which the completion keys are written in and
  /// which places today's cell in each panel.
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Label(String(localized: "habits.detail.visualization.title", defaultValue: "Progress", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "chart.xyaxis.line")
        .font(LorvexDesign.Typography.sectionHeader)
        .accessibilityAddTraits(.isHeader)

      if let detail {
        MobileHabitMomentumPanel(habit: habit, stats: detail.stats, timeZone: productTimeZone)
        MobileHabitRhythmPanel(habit: habit, stats: detail.stats, timeZone: productTimeZone)
        MobileHabitHeatmapPanel(habit: habit, detail: detail, timeZone: productTimeZone)
      } else {
        MobileSkeletonRows(count: 3, showsTrailingDetail: true)
        .padding(LorvexDesign.Spacing.l)
        .background(
          LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
        .accessibilityIdentifier("mobileHabits.detail.visualization.loading")
      }
    }
    .accessibilityIdentifier("mobileHabits.detail.visualization")
  }
}

/// The period's progress, the streaks, and the 30-day rate. The dial and its
/// caption lead, beside the three stats where the width holds them all
/// (an iPad pane), over them as three columns on a phone, and over three rows
/// of a label and its value where the three columns do not fit whole (long
/// labels, accessibility text sizes). A column is as wide as its label and
/// value, so no label breaks, and the values share one baseline.
private struct MobileHabitMomentumPanel: View {
  let habit: LorvexHabit
  let stats: HabitStats
  let timeZone: TimeZone

  private enum StatLayout { case column, row }

  private var progress: HabitPeriodProgress.Value {
    HabitPeriodProgress.current(
      habit: habit, recentCompletions: stats.recentCompletions, recentSkips: stats.recentSkips,
      timeZone: timeZone)
  }

  /// Today was set aside and the dial counts today: it shows the skip, not a
  /// count of check-ins the day has none of.
  private var isSetAside: Bool { HabitPeriodProgress.isSetAside(habit) }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        // Laid out before the stats, whose gaps stretch, so the title beside
        // the ring keeps its one line instead of taking a quarter of the width.
        ring.layoutPriority(1)
        statColumns
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        ring
        statColumns
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        ring
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          statViews(.row)
        }
      }
    }
    .padding(LorvexDesign.Spacing.l)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(momentumAccessibilityLabel)
    .accessibilityIdentifier("mobileHabits.detail.momentum")
  }

  /// The dial with the period's name and count, beside it while both fit
  /// whole and under it in a narrower width.
  private var ring: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        dial
        periodText
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        dial
        periodText
      }
    }
  }

  private var dial: some View {
    MobileHabitMomentumDial(
      completed: progress.completed, required: progress.required, fraction: fraction, tint: tint,
      isSkipped: isSetAside
    )
    // Past the first accessibility size the dial would crowd its caption off
    // the line; it keeps that size, the count inside it included.
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }

  private var periodText: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(periodTitle)
        .font(LorvexDesign.Typography.primaryEmphasis)
      Text(periodCaption)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
    }
  }

  /// The period the ring counts over, named plainly: "Today" for a daily habit
  /// or any per-day target, "This Week" or "This Month" for the longer cadences.
  private var periodTitle: String {
    switch HabitPeriodProgress.period(for: habit) {
    case .day:
      String(localized: "habits.detail.today", defaultValue: "Today", table: "Localizable", bundle: MobileL10n.bundle)
    case .week:
      String(localized: "habits.detail.this_week", defaultValue: "This Week", table: "Localizable", bundle: MobileL10n.bundle)
    case .month:
      String(localized: "habits.detail.this_month", defaultValue: "This Month", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// The three stats as columns at their own widths, with the width left over
  /// spread between them, and their values on one baseline.
  private var statColumns: some View {
    HStack(alignment: .lastTextBaseline, spacing: 0) {
      statViews(.column)
    }
  }

  /// The current streak, the best streak, and the 30-day rate, each laid out
  /// as `layout` says, with a flexible gap between columns. Written out rather
  /// than looped: a `ViewThatFits` candidate holds no `ForEach`.
  @ViewBuilder
  private func statViews(_ layout: StatLayout) -> some View {
    stat(
      layout,
      title: LocalizedStringResource(
        "habits.detail.current_streak",
        defaultValue: "Current Streak",
        table: "Localizable",
        bundle: MobileL10n.bundle),
      value: lorvexHabitStreakLabel(stats.currentStreak, frequencyType: habit.frequencyType),
      tint: currentStreakTint)
    if layout == .column { Spacer(minLength: LorvexDesign.Spacing.m) }
    stat(
      layout,
      title: LocalizedStringResource(
        "habits.detail.best_streak",
        defaultValue: "Best Streak",
        table: "Localizable",
        bundle: MobileL10n.bundle),
      value: lorvexHabitStreakLabel(stats.bestStreak, frequencyType: habit.frequencyType),
      tint: bestStreakTint)
    if layout == .column { Spacer(minLength: LorvexDesign.Spacing.m) }
    stat(
      layout,
      title: LocalizedStringResource(
        "habits.detail.rate_30d",
        defaultValue: "Last 30 Days",
        table: "Localizable",
        bundle: MobileL10n.bundle),
      value: stats.completionRate30d.formatted(.percent.precision(.fractionLength(0))),
      tint: rateTint)
  }

  /// A stat as a column (its label over its value, as wide as the wider of
  /// the two, so neither breaks) or as a row (its label, then its value at the
  /// trailing edge).
  @ViewBuilder
  private func stat(_ layout: StatLayout, title: LocalizedStringResource, value: String, tint: Color)
    -> some View
  {
    let label = Text(title)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
    let reading = Text(value)
      .font(LorvexDesign.Typography.primaryEmphasis)
      .foregroundStyle(tint)
      .monospacedDigit()
    switch layout {
    case .column:
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        label
        reading
      }
      .fixedSize()
    case .row:
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        label
        Spacer(minLength: LorvexDesign.Spacing.s)
        reading
          .fixedSize()
      }
    }
  }

  private var tint: Color {
    progress.isComplete ? LorvexDesign.Palette.done : habit.tileTint
  }

  /// The current-streak stat tint: the habit's own identity color while the
  /// streak is active (non-zero), `neutral` once it has broken to zero.
  private var currentStreakTint: Color {
    stats.currentStreak > 0 ? habit.tileTint : LorvexDesign.Palette.neutral
  }

  /// The best-streak stat tint: the habit's own identity color once a streak
  /// has been recorded, `neutral` when the habit has never held one.
  private var bestStreakTint: Color {
    stats.bestStreak > 0 ? habit.tileTint : LorvexDesign.Palette.neutral
  }

  /// The 30-day rate tint: the habit's own identity color once the window
  /// holds a check-in, `neutral` at 0%, like the streaks beside it.
  private var rateTint: Color {
    stats.completionRate30d > 0 ? habit.tileTint : LorvexDesign.Palette.neutral
  }

  private var fraction: Double {
    guard progress.required > 0 else { return 0 }
    return min(1, Double(progress.completed) / Double(progress.required))
  }

  /// What the period still asks for. The dial already shows the count done
  /// over the count required, so the caption says how many remain ("2 to go")
  /// or that the period is done. A day set aside says so instead.
  private var periodCaption: String {
    if isSetAside { return MobileHabitSkipCopy.skippedToday }
    if progress.isComplete {
      return String(localized: "habits.detail.period_done", defaultValue: "Done", table: "Localizable", bundle: MobileL10n.bundle)
    }
    let remaining = max(progress.required - progress.completed, 1)
    return String(
      localized: "habits.detail.period_remaining", defaultValue: "\(remaining) to go",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  private var momentumAccessibilityLabel: String {
    if isSetAside {
      return String(
        localized: "habits.detail.momentum.skipped.a11y",
        defaultValue: "Skipped today, current streak \(stats.currentStreak), best streak \(stats.bestStreak)",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(
      localized: "habits.detail.momentum.a11y",
      defaultValue: "Period progress \(progress.completed) of \(progress.required), current streak \(stats.currentStreak), best streak \(stats.bestStreak)",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}

/// The period's progress as a ring around its count, the count done over the
/// count required ("2" over "/3"). The ring, its stroke, and the count grow
/// with the text together. A day set aside draws the ring as dots around the
/// skip glyph, the marks a skipped habit wears in its row, so the day reads as
/// excused by shape and not by color alone.
private struct MobileHabitMomentumDial: View {
  let completed: Int
  let required: Int
  /// How much of the ring is drawn, from 0 to 1.
  let fraction: Double
  let tint: Color
  /// The day was set aside: dots and the skip glyph replace the arc and count.
  var isSkipped: Bool = false
  @Environment(\.colorScheme) private var colorScheme
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 74
  @ScaledMetric(relativeTo: .body) private var lineWidth: CGFloat = 8

  var body: some View {
    ZStack {
      if isSkipped {
        LorvexDottedRing(dotDiameter: lineWidth)
          .fill(.tertiary)
        Image(systemName: LorvexHabitSkip.glyph)
          .font(.system(.title3, design: .rounded).weight(.semibold))
          .foregroundStyle(Color.secondary)
          .accessibilityHidden(true)
      } else {
        Circle()
          .stroke(
            tint.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)),
            lineWidth: lineWidth)
        LorvexProgressArc(fraction: fraction, style: tint.gradient, lineWidth: lineWidth)
          .reduceMotionAnimation(.easeInOut(duration: 0.25), value: fraction)
        VStack(spacing: 1) {
          Text("\(completed)")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text("/\(required)")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
    }
    .frame(width: size, height: size)
  }
}

/// The recent periods as capsules, the current one ringed. A daily habit's
/// seven days carry their narrow weekday underneath, today's in the habit's
/// color and the others in the secondary style (they name the days, so they
/// stay legible), so the strip reads as "this week" rather than seven
/// anonymous marks; a weekly or monthly strip stays unlabeled.
private struct MobileHabitRhythmPanel: View {
  let habit: LorvexHabit
  let stats: HabitStats
  let timeZone: TimeZone

  private var cells: [HabitRhythmStrip.Cell] {
    HabitRhythmStrip.cells(
      completions: Set(stats.recentCompletions),
      skips: Set(stats.recentSkips),
      habit: habit,
      today: Date(),
      timeZone: timeZone
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(String(localized: "habits.detail.rhythm", defaultValue: "Rhythm", table: "Localizable", bundle: MobileL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      let labels = dayLabels
      HStack(alignment: .top, spacing: 5) {
        ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
          VStack(spacing: LorvexDesign.Spacing.xs) {
            Capsule()
              // A skipped day's track is not filled: its dashed outline stands in.
              .fill(cell.filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(cell.isSkipped ? 0 : 0.18)))
              .frame(height: 14)
              .overlay {
                if cell.isSkipped {
                  // The day was set aside, neither done nor missed.
                  Capsule().strokeBorder(
                    cell.isCurrent ? tint.opacity(0.7) : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else if cell.isCurrent {
                  Capsule().strokeBorder(tint.opacity(cell.filled ? 0.35 : 0.7), lineWidth: 1)
                }
              }
            if index < labels.count {
              Text(labels[index])
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(cell.isCurrent ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .fixedSize()
            }
          }
        }
      }
    }
    .padding(LorvexDesign.Spacing.l)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rhythmAccessibilityLabel)
    .accessibilityIdentifier("mobileHabits.detail.rhythm")
  }

  private var tint: Color { habit.tileTint }

  private var dayLabels: [String] {
    HabitRhythmStrip.dayLabels(habit: habit, today: Date(), timeZone: timeZone)
  }

  private var rhythmAccessibilityLabel: String {
    let filled = cells.filter(\.filled).count
    return String(
      localized: "habits.detail.rhythm.a11y",
      defaultValue: "Rhythm strip: \(filled) of \(cells.count) periods completed",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}

/// Lays out a habit heatmap's `weeks` week columns, oldest to newest, then
/// any month labels, one per week in the same order. It shows as many of the
/// newest weeks as the proposed width fits at the fixed cell size, between a
/// season and a year: a phone shows about five months, an iPad pane or a
/// readable-width screen the whole year. The columns that do not fit are
/// placed far outside the bounds, so what shows always ends on the current
/// week. The count is decided here, per layout pass, rather than measured
/// into view state: a navigation transition proposes alternating widths to
/// the incoming screen, and state derived from them flips every frame. The
/// month labels sit at the top of the columns where
/// ``HabitHeatmapModel/monthLabelPositions(starts:widths:leadingEdge:trailingEdge:gap:)``
/// puts them at their own widths; a label it leaves out goes outside the
/// bounds with the hidden weeks.
struct MobileHabitHeatmapLayout: Layout {
  static let minimumWeeks = 16
  static let maximumWeeks = 52
  static let cellSize: CGFloat = 10
  static let cellSpacing: CGFloat = 3
  /// The least room between two month labels.
  static let labelGap: CGFloat = 4

  /// How many of the subviews are week columns.
  let weeks: Int

  /// The columns shown of `count` in `width`: the newest that fit at the cell
  /// size and spacing, at least `minimumWeeks` (overflowing a narrower width),
  /// and all of them for an unbounded width.
  static func shownColumns(of count: Int, fitting width: CGFloat?) -> Int {
    guard let width, width.isFinite else { return count }
    let fitted = Int(max(0, width + cellSpacing) / (cellSize + cellSpacing))
    return min(count, max(minimumWeeks, fitted))
  }

  static func width(ofColumns count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return CGFloat(count) * (cellSize + cellSpacing) - cellSpacing
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let shown = Self.shownColumns(of: min(weeks, subviews.count), fitting: proposal.width)
    let height = subviews.first?.sizeThatFits(.unspecified).height ?? 0
    return CGSize(width: Self.width(ofColumns: shown), height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let count = min(weeks, subviews.count)
    let shown = Self.shownColumns(of: count, fitting: bounds.width)
    let hidden = count - shown
    let starts: [CGFloat?] = (0..<count).map { index in
      index < hidden ? nil : bounds.minX + CGFloat(index - hidden) * (Self.cellSize + Self.cellSpacing)
    }
    let outside = bounds.minX - 100_000
    for (index, subview) in subviews.prefix(count).enumerated() {
      subview.place(
        at: CGPoint(x: starts[index] ?? outside, y: bounds.minY), anchor: .topLeading,
        proposal: .unspecified)
    }
    let labels = Array(subviews.dropFirst(count))
    guard !labels.isEmpty else { return }
    let positions = HabitHeatmapModel.monthLabelPositions(
      starts: starts, widths: labels.map { $0.sizeThatFits(.unspecified).width },
      leadingEdge: bounds.minX, trailingEdge: bounds.minX + Self.width(ofColumns: shown),
      gap: Self.labelGap)
    for (index, label) in labels.enumerated() {
      let x = positions.indices.contains(index) ? positions[index] : nil
      label.place(
        at: CGPoint(x: x ?? outside, y: bounds.minY), anchor: .topLeading, proposal: .unspecified)
    }
  }
}

private struct MobileHabitHeatmapPanel: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail
  @State private var cachedGrid: HabitHeatmapModel.Grid

  private let calendar: Calendar

  init(habit: LorvexHabit, detail: MobileStore.HabitDetail, timeZone: TimeZone) {
    self.habit = habit
    self.detail = detail
    let calendar = Self.makeCalendar(timeZone)
    self.calendar = calendar
    _cachedGrid = State(initialValue: Self.makeGrid(habit: habit, detail: detail, calendar: calendar))
  }

  /// The grid's calendar: Gregorian in `timeZone`, the product time zone the
  /// completion keys are written in, with ISO weeks (Monday first), the weeks
  /// a habit's progress counts, so a column of a weekly habit is one of its
  /// periods, as in the Mac's History panel.
  private static func makeCalendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      // The title and the legend share a line while both fit whole; in a
      // narrower line (at accessibility text sizes) the legend moves under
      // the title rather than squeezing it into a broken word.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          title
            .lineLimit(1)
          Spacer(minLength: LorvexDesign.Spacing.s)
          legend
        }
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          title
            .fixedSize(horizontal: false, vertical: true)
          legend
        }
      }
      if detail.completions.completions.isEmpty {
        Text(String(localized: "habits.detail.heatmap.empty", defaultValue: "No completion history yet", table: "Localizable", bundle: MobileL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
      MobileHabitHeatmapGrid(grid: cachedGrid, calendar: calendar, tint: tint)
        // The cells keep one size at every text size, so the month and
        // weekday labels stop growing where a month's name would outgrow
        // its month's columns.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    // The grid shows whole weeks, so it falls short of the width by up to a
    // column; the card still spans the width, edge to edge with the panels
    // above it, and the grid keeps to its leading side.
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(LorvexDesign.Spacing.l)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    // The grid places the weeks that do not fit 100,000pt outside its
    // bounds, and one VoiceOver element made of the panel's content would
    // take that whole span as its frame. The content is hidden from
    // VoiceOver and an overlay the size of the card carries the label.
    .accessibilityHidden(true)
    .overlay {
      Color.clear
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heatmapAccessibilityLabel)
        .accessibilityIdentifier("mobileHabits.detail.heatmap")
    }
    .onChange(of: detail) { _, _ in
      refreshCachedGrid()
    }
    .onChange(of: habit.targetCount) { _, _ in
      refreshCachedGrid()
    }
    .onChange(of: calendar.timeZone) { _, _ in
      refreshCachedGrid()
    }
  }

  private var title: some View {
    Text(String(localized: "habits.detail.heatmap", defaultValue: "Completion Heatmap", table: "Localizable", bundle: MobileL10n.bundle))
      .font(LorvexDesign.Typography.primaryEmphasis)
  }

  /// The cell states the grid draws, in the grid's own cells and capped at the
  /// grid's text size: the three between "Less" and "More", then, once the year
  /// holds a skipped day, the skipped cell, which is off that scale.
  private var legend: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Text(String(localized: "habits.detail.heatmap.legend.less", defaultValue: "Less", table: "Localizable", bundle: MobileL10n.bundle))
      MobileHabitHeatmapCell(intensity: .none, tint: tint)
      MobileHabitHeatmapCell(intensity: .partial, tint: tint)
      MobileHabitHeatmapCell(intensity: .met, tint: tint)
      Text(String(localized: "habits.detail.heatmap.legend.more", defaultValue: "More", table: "Localizable", bundle: MobileL10n.bundle))
      if hasSkippedDays {
        MobileHabitHeatmapCell(intensity: .skipped, tint: tint)
          .padding(.leading, LorvexDesign.Spacing.s)
        Text(String(localized: "habits.detail.heatmap.legend.skipped", defaultValue: "Skipped", table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .fixedSize()
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .accessibilityHidden(true)
  }

  private var tint: Color {
    habit.tileTint
  }

  private var hasSkippedDays: Bool {
    cachedGrid.columns.contains { column in column.contains { $0.intensity == .skipped } }
  }

  private func refreshCachedGrid() {
    cachedGrid = Self.makeGrid(habit: habit, detail: detail, calendar: calendar)
  }

  /// The whole year, of which the layout shows what fits.
  private static func makeGrid(
    habit: LorvexHabit,
    detail: MobileStore.HabitDetail,
    calendar: Calendar
  ) -> HabitHeatmapModel.Grid {
    HabitHeatmapModel.makeGrid(
      completions: detail.completions.completions,
      targetCount: habit.targetCount,
      weeks: MobileHabitHeatmapLayout.maximumWeeks,
      endDate: Date(),
      calendar: calendar,
      skips: Set(detail.stats.recentSkips)
    )
  }

  /// Describes the year the grid holds, not only the columns on screen.
  private var heatmapAccessibilityLabel: String {
    let cells = cachedGrid.columns.flatMap { $0 }
    let met = cells.filter { $0.intensity == .met }.count
    let partial = cells.filter { $0.intensity == .partial }.count
    return MobileHabitAccessibilityText.heatmapLabel(
      weeks: cachedGrid.columns.count, targetMetDays: met, partialDays: partial)
  }
}

/// The heatmap's cells, a week to a column under the month labels, beside a
/// column of weekday initials. A month is named where it begins, in the
/// calendar the app shows dates in (Hijri months under an Islamic calendar);
/// a name that would run into the next month's is left out. The cells have
/// one size at every text size; the labels' row and column grow with the
/// labels' text, which the panel caps.
private struct MobileHabitHeatmapGrid: View {
  let grid: HabitHeatmapModel.Grid
  let calendar: Calendar
  let tint: Color

  private let cellSize = MobileHabitHeatmapLayout.cellSize
  private let cellSpacing = MobileHabitHeatmapLayout.cellSpacing
  @ScaledMetric(relativeTo: .caption) private var weekdayLabelWidth: CGFloat = 10

  var body: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      weekdayColumn
      MobileHabitHeatmapLayout(weeks: grid.columns.count) {
        ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
          weekColumn(column)
        }
        ForEach(Array(grid.monthLabels.enumerated()), id: \.offset) { _, label in
          monthLabel(label)
        }
      }
    }
  }

  /// The month labels' row: one line of the label text, empty, so the
  /// weekday column and every week column start their cells at one height.
  private func monthRow(width: CGFloat) -> some View {
    Text(verbatim: " ")
      .font(LorvexDesign.Typography.tertiaryText)
      .hidden()
      .frame(width: width, alignment: .leading)
  }

  private var weekdayColumn: some View {
    VStack(alignment: .leading, spacing: cellSpacing) {
      monthRow(width: weekdayLabelWidth)
      ForEach(Array(HabitHeatmapModel.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { index, symbol in
        Text(index.isMultiple(of: 2) ? symbol : " ")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(minWidth: weekdayLabelWidth, minHeight: cellSize, maxHeight: cellSize, alignment: .leading)
      }
    }
  }

  /// One week: the month labels' row, over the day cells.
  private func weekColumn(_ column: [HabitHeatmapModel.Cell]) -> some View {
    VStack(spacing: cellSpacing) {
      monthRow(width: cellSize)
      ForEach(column) { cell in
        MobileHabitHeatmapCell(intensity: cell.intensity, tint: tint)
      }
    }
  }

  /// The name of the month a week begins, at its own width, or nothing for a
  /// week no month begins in; ``MobileHabitHeatmapLayout`` places it.
  private func monthLabel(_ label: String?) -> some View {
    Text(verbatim: label ?? "")
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .fixedSize()
  }
}

/// One day of the heatmap: a rounded square filled by how far the day went
/// toward its target, with a mark that tells the states apart without color
/// (a slash for part of the target, a dot for the target met). A skipped day
/// has a dashed outline in place of a fill.
private struct MobileHabitHeatmapCell: View {
  let intensity: HabitHeatmapModel.Intensity
  let tint: Color

  private let size = MobileHabitHeatmapLayout.cellSize

  var body: some View {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
      .fill(fill)
      .overlay { cue }
      .frame(width: size, height: size)
  }

  @ViewBuilder
  private var cue: some View {
    switch intensity {
    case .partial:
      Capsule()
        .fill(tint.opacity(0.7))
        .frame(width: size * 0.35, height: 2)
        .rotationEffect(.degrees(-45))
    case .met:
      Circle()
        .fill(.primary.opacity(0.22))
        .frame(width: size * 0.42, height: size * 0.42)
    case .skipped:
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
        .strokeBorder(.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
    case .absent, .none:
      EmptyView()
    }
  }

  private var fill: AnyShapeStyle {
    switch intensity {
    case .absent, .skipped:
      return AnyShapeStyle(Color.clear)
    case .none:
      return AnyShapeStyle(.quaternary)
    case .partial:
      return AnyShapeStyle(tint.opacity(0.42))
    case .met:
      return AnyShapeStyle(tint)
    }
  }
}

private enum MobileHabitAccessibilityText {
  static func heatmapLabel(
    weeks: Int,
    targetMetDays: Int,
    partialDays: Int
  ) -> String {
    let weeksText = String(
      localized: "habits.detail.heatmap.weeks_count", defaultValue: "\(weeks) weeks",
      table: "Localizable", bundle: MobileL10n.bundle)
    let targetMetText = String(
      localized: "habits.detail.heatmap.met_days_count",
      defaultValue: "Target met on \(targetMetDays) days",
      table: "Localizable", bundle: MobileL10n.bundle)
    let partialText = String(
      localized: "habits.detail.heatmap.partial_days_count",
      defaultValue: "\(partialDays) partial days",
      table: "Localizable", bundle: MobileL10n.bundle)
    return String(
      format: String(
        localized: "habits.detail.heatmap.a11y",
        defaultValue: "Completion heatmap covering %1$@. %2$@. %3$@.",
        table: "Localizable", bundle: MobileL10n.bundle),
      weeksText,
      targetMetText,
      partialText
    )
  }
}
