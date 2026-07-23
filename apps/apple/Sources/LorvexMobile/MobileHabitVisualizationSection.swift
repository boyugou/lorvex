import LorvexCore
import SwiftUI

struct MobileHabitVisualizationSection: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      Label(String(localized: "habits.detail.visualization.title", defaultValue: "Progress", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "chart.xyaxis.line")
        .font(LorvexDesign.Typography.sectionHeader)

      if let detail {
        MobileHabitMomentumPanel(habit: habit, stats: detail.stats)
        MobileHabitRhythmPanel(habit: habit, stats: detail.stats)
        MobileHabitHeatmapPanel(habit: habit, detail: detail)
      } else {
        MobileSkeletonRows(count: 3, showsTrailingDetail: true)
        .padding(LorvexDesign.Spacing.l)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("mobileHabits.detail.visualization.loading")
      }
    }
    .accessibilityIdentifier("mobileHabits.detail.visualization")
  }
}

private struct MobileHabitMomentumPanel: View {
  let habit: LorvexHabit
  let stats: HabitStats
  @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 74
  @ScaledMetric(relativeTo: .body) private var ringLineWidth: CGFloat = 8

  private var progress: HabitPeriodProgress.Value {
    HabitPeriodProgress.current(habit: habit, recentCompletions: stats.recentCompletions)
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.m) {
        ring
        stat(
          title: LocalizedStringResource(
            "habits.detail.current_streak",
            defaultValue: "Current Streak",
            table: "Localizable",
            bundle: MobileL10n.bundle),
          value: "\(stats.currentStreak)",
          tint: .orange)
        stat(
          title: LocalizedStringResource(
            "habits.detail.best_streak",
            defaultValue: "Best Streak",
            table: "Localizable",
            bundle: MobileL10n.bundle),
          value: "\(stats.bestStreak)",
          tint: .orange)
        stat(
          title: LocalizedStringResource(
            "habits.detail.rate_30d",
            defaultValue: "30-day",
            table: "Localizable",
            bundle: MobileL10n.bundle),
          value: stats.completionRate30d.formatted(.percent.precision(.fractionLength(0))),
          tint: .accentColor)
      }
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        ring
        HStack(spacing: LorvexDesign.Spacing.m) {
          stat(
            title: LocalizedStringResource(
              "habits.detail.current_streak",
              defaultValue: "Current Streak",
              table: "Localizable",
              bundle: MobileL10n.bundle),
            value: "\(stats.currentStreak)",
            tint: .orange)
          stat(
            title: LocalizedStringResource(
              "habits.detail.best_streak",
              defaultValue: "Best Streak",
              table: "Localizable",
              bundle: MobileL10n.bundle),
            value: "\(stats.bestStreak)",
            tint: .orange)
          stat(
            title: LocalizedStringResource(
              "habits.detail.rate_30d",
              defaultValue: "30-day",
              table: "Localizable",
              bundle: MobileL10n.bundle),
            value: stats.completionRate30d.formatted(.percent.precision(.fractionLength(0))),
            tint: .accentColor)
        }
      }
    }
    .padding(LorvexDesign.Spacing.l)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(momentumAccessibilityLabel)
    .accessibilityIdentifier("mobileHabits.detail.momentum")
  }

  private var ring: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      ZStack {
        Circle()
          .stroke(tint.opacity(0.18), lineWidth: ringLineWidth)
        Circle()
          .trim(from: 0, to: fraction)
          .stroke(tint.gradient, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut(duration: 0.25), value: fraction)
        VStack(spacing: 1) {
          Text("\(progress.completed)")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text("/\(progress.required)")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
      .frame(width: ringSize, height: ringSize)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(String(localized: "habits.detail.period_progress", defaultValue: "Period Progress", table: "Localizable", bundle: MobileL10n.bundle))
          .font(LorvexDesign.Typography.primaryEmphasis)
        Text(periodCaption)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }

  private func stat(title: LocalizedStringResource, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      Text(value)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(tint)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var tint: Color {
    progress.isComplete ? .green : habit.tileTint
  }

  private var fraction: Double {
    guard progress.required > 0 else { return 0 }
    return min(1, Double(progress.completed) / Double(progress.required))
  }

  private var periodCaption: String {
    String(
      format: String(localized: "habits.detail.period_progress.value", defaultValue: "%1$lld of %2$lld done", table: "Localizable", bundle: MobileL10n.bundle),
      progress.completed,
      progress.required
    )
  }

  private var momentumAccessibilityLabel: String {
    String(
      format: String(localized: "habits.detail.momentum.a11y", defaultValue: "Period progress %1$lld of %2$lld, current streak %3$lld, best streak %4$lld", table: "Localizable", bundle: MobileL10n.bundle),
      progress.completed,
      progress.required,
      stats.currentStreak,
      stats.bestStreak
    )
  }
}

private struct MobileHabitRhythmPanel: View {
  let habit: LorvexHabit
  let stats: HabitStats

  private var cells: [HabitRhythmStrip.Cell] {
    HabitRhythmStrip.cells(
      completions: Set(stats.recentCompletions),
      habit: habit,
      today: Date()
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(String(localized: "habits.detail.rhythm", defaultValue: "Rhythm", table: "Localizable", bundle: MobileL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      HStack(spacing: 5) {
        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
          Capsule()
            .fill(cell.filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.18)))
            .overlay {
              if cell.isCurrent {
                Capsule().strokeBorder(tint.opacity(cell.filled ? 0.35 : 0.7), lineWidth: 1)
              }
            }
        }
      }
      .frame(height: 14)
    }
    .padding(LorvexDesign.Spacing.l)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rhythmAccessibilityLabel)
    .accessibilityIdentifier("mobileHabits.detail.rhythm")
  }

  private var tint: Color { habit.tileTint }

  private var rhythmAccessibilityLabel: String {
    let filled = cells.filter(\.filled).count
    return String(
      format: String(localized: "habits.detail.rhythm.a11y", defaultValue: "Rhythm strip: %1$lld of %2$lld periods completed", table: "Localizable", bundle: MobileL10n.bundle),
      filled,
      cells.count
    )
  }
}

private struct MobileHabitHeatmapPanel: View {
  let habit: LorvexHabit
  let detail: MobileStore.HabitDetail
  @State private var cachedGrid: HabitHeatmapModel.Grid

  private static let defaultWeeks = 16
  private let weeks = Self.defaultWeeks
  private let cellSize: CGFloat = 10
  private let cellSpacing: CGFloat = 3
  @ScaledMetric(relativeTo: .caption) private var weekdayLabelWidth: CGFloat = 10

  private let calendar: Calendar

  init(habit: LorvexHabit, detail: MobileStore.HabitDetail) {
    self.habit = habit
    self.detail = detail
    let calendar = Self.makeCalendar()
    self.calendar = calendar
    _cachedGrid = State(initialValue: Self.makeGrid(
      habit: habit,
      detail: detail,
      weeks: Self.defaultWeeks,
      calendar: calendar
    ))
  }

  private static func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      HStack {
        Text(String(localized: "habits.detail.heatmap", defaultValue: "Completion Heatmap", table: "Localizable", bundle: MobileL10n.bundle))
          .font(LorvexDesign.Typography.primaryEmphasis)
        Spacer()
        legend
      }
      if detail.completions.completions.isEmpty {
        Text(String(localized: "habits.detail.heatmap.empty", defaultValue: "No completion history yet", table: "Localizable", bundle: MobileL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
      heatmap
    }
    .padding(LorvexDesign.Spacing.l)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(heatmapAccessibilityLabel)
    .accessibilityIdentifier("mobileHabits.detail.heatmap")
    .onChange(of: detail) { _, _ in
      refreshCachedGrid()
    }
    .onChange(of: habit.targetCount) { _, _ in
      refreshCachedGrid()
    }
  }

  private var heatmap: some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      weekdayColumn
      VStack(alignment: .leading, spacing: cellSpacing) {
        monthRow
        HStack(alignment: .top, spacing: cellSpacing) {
          ForEach(Array(cachedGrid.columns.enumerated()), id: \.offset) { _, column in
            VStack(spacing: cellSpacing) {
              ForEach(column) { cell in
                cellView(cell)
              }
            }
          }
        }
      }
    }
  }

  private var weekdayColumn: some View {
    VStack(alignment: .leading, spacing: cellSpacing) {
      Text(" ")
        .font(LorvexDesign.Typography.tertiaryText)
      ForEach(Array(HabitHeatmapModel.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { index, symbol in
        Text(index.isMultiple(of: 2) ? symbol : " ")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .frame(minWidth: weekdayLabelWidth, minHeight: cellSize, alignment: .leading)
      }
    }
  }

  private var monthRow: some View {
    HStack(spacing: cellSpacing) {
      ForEach(Array(cachedGrid.monthLabels.enumerated()), id: \.offset) { _, label in
        Color.clear
          .frame(width: cellSize, height: 13)
          .overlay(alignment: .leading) {
            if let label {
              Text(label)
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            }
          }
      }
    }
  }

  private var legend: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Text(String(localized: "habits.detail.heatmap.legend.less", defaultValue: "Less", table: "Localizable", bundle: MobileL10n.bundle))
      ForEach([HabitHeatmapModel.Intensity.none, .partial, .met], id: \.self) { intensity in
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(fill(for: intensity))
          .frame(width: cellSize, height: cellSize)
      }
      Text(String(localized: "habits.detail.heatmap.legend.more", defaultValue: "More", table: "Localizable", bundle: MobileL10n.bundle))
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.secondary)
    .accessibilityHidden(true)
  }

  private func cellView(_ cell: HabitHeatmapModel.Cell) -> some View {
    RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(fill(for: cell.intensity))
      .overlay {
        cue(for: cell.intensity)
      }
      .frame(width: cellSize, height: cellSize)
  }

  @ViewBuilder
  private func cue(for intensity: HabitHeatmapModel.Intensity) -> some View {
    switch intensity {
    case .partial:
      Capsule()
        .fill(tint.opacity(0.7))
        .frame(width: cellSize * 0.35, height: 2)
        .rotationEffect(.degrees(-45))
    case .met:
      Circle()
        .fill(.primary.opacity(0.22))
        .frame(width: cellSize * 0.42, height: cellSize * 0.42)
    case .absent, .none:
      EmptyView()
    }
  }

  private func fill(for intensity: HabitHeatmapModel.Intensity) -> AnyShapeStyle {
    switch intensity {
    case .absent:
      return AnyShapeStyle(Color.clear)
    case .none:
      return AnyShapeStyle(.quaternary)
    case .partial:
      return AnyShapeStyle(tint.opacity(0.42))
    case .met:
      return AnyShapeStyle(tint)
    }
  }

  private var tint: Color {
    habit.tileTint
  }

  private func refreshCachedGrid() {
    cachedGrid = Self.makeGrid(
      habit: habit,
      detail: detail,
      weeks: weeks,
      calendar: calendar
    )
  }

  private static func makeGrid(
    habit: LorvexHabit,
    detail: MobileStore.HabitDetail,
    weeks: Int,
    calendar: Calendar
  ) -> HabitHeatmapModel.Grid {
    HabitHeatmapModel.makeGrid(
      completions: detail.completions.completions,
      targetCount: habit.targetCount,
      weeks: weeks,
      endDate: Date(),
      calendar: calendar
    )
  }

  private var heatmapAccessibilityLabel: String {
    let cells = cachedGrid.columns.flatMap { $0 }
    let met = cells.filter { $0.intensity == .met }.count
    let partial = cells.filter { $0.intensity == .partial }.count
    return MobileHabitAccessibilityText.heatmapLabel(
      weeks: weeks, targetMetDays: met, partialDays: partial)
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
