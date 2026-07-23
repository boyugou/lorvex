import LorvexCore
import SwiftUI

/// A GitHub-contributions-style heatmap of a habit's recent completion history,
/// plus its key stats (current streak, best streak, 30-day completion rate).
///
/// Renders the trailing `weeks` weeks as a column-per-week grid of small
/// rounded cells whose fill reflects each day's summed completions against the
/// habit's target on a graded five-shade ramp (`HabitHeatmapModel.Cell.level`):
/// no activity → a neutral quaternary wash, then four steps of the app accent up
/// to a full-accent "met" cell; days outside the window are empty slots. The
/// ramp is opacity steps of the environment `.tint` (the user's Apple accent),
/// so it stays token-derived and renders correctly in light and dark.
///
/// Data comes from the store's cached `HabitDetail` (completions + stats),
/// which the caller loads via `AppStore.loadHabitDetail(id:)`.
struct HabitHeatmapView: View {
  let habit: LorvexHabit
  let detail: AppStore.HabitDetail?
  @State private var cachedGrid: HabitHeatmapModel.Grid

  private let weeks = 12
  private let cellSize: CGFloat = 11
  private let cellSpacing: CGFloat = 3

  /// Fixed-timezone Gregorian calendar driving column alignment and date keys.
  /// Stored (not computed) so each render reuses one instance instead of
  /// rebuilding it.
  private let calendar: Calendar

  init(habit: LorvexHabit, detail: AppStore.HabitDetail?) {
    self.habit = habit
    self.detail = detail
    let calendar = Self.makeCalendar()
    self.calendar = calendar
    _cachedGrid = State(initialValue: Self.makeGrid(
      habit: habit,
      detail: detail,
      weeks: weeks,
      calendar: calendar
    ))
  }

  private static func makeCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HabitHeatmapStatsLine(
        habitID: habit.id, stats: detail?.stats, frequencyType: habit.frequencyType)
      if detail != nil {
        heatmap(grid: cachedGrid)
        legend
      } else {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(String(localized: "habits.heatmap.loading_a11y", defaultValue: "Loading habit history", table: "Localizable", bundle: LorvexL10n.bundle))
      }
    }
    .padding(.top, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("habit.heatmap.\(habit.id)")
    .onChange(of: detail) { _, _ in
      refreshCachedGrid()
    }
    .onChange(of: habit.targetCount) { _, _ in
      refreshCachedGrid()
    }
  }

  // MARK: Heatmap grid

  private func heatmap(grid: HabitHeatmapModel.Grid) -> some View {
    HStack(alignment: .top, spacing: cellSpacing) {
      weekdayColumn
      VStack(alignment: .leading, spacing: cellSpacing) {
        monthRow(grid: grid)
        HStack(alignment: .top, spacing: cellSpacing) {
          ForEach(Array(grid.columns.enumerated()), id: \.offset) { _, column in
            VStack(spacing: cellSpacing) {
              ForEach(column) { cell in
                cellView(cell)
              }
            }
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(heatmapAccessibilityLabel(grid: grid))
    .accessibilityIdentifier("habit.heatmap.grid.\(habit.id)")
  }

  private var weekdayColumn: some View {
    VStack(alignment: .leading, spacing: cellSpacing) {
      // Spacer matching the month label row height so weekdays align to cells.
      Text(" ")
        .font(LorvexDesign.Typography.tertiaryText)
      ForEach(Array(HabitHeatmapModel.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) {
        index, symbol in
        Text(index.isMultiple(of: 2) ? symbol : " ")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .frame(width: cellSize, height: cellSize)
      }
    }
  }

  private func monthRow(grid: HabitHeatmapModel.Grid) -> some View {
    // Each slot keeps the column width for alignment with the cells below, but
    // the label is drawn as a leading overlay so a two-character month ("4月")
    // overflows into the empty neighbour slots instead of wrapping to two lines.
    HStack(spacing: cellSpacing) {
      ForEach(Array(grid.monthLabels.enumerated()), id: \.offset) { _, label in
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

  private func cellView(_ cell: HabitHeatmapModel.Cell) -> some View {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
      .fill(fill(for: cell))
      .frame(width: cellSize, height: cellSize)
  }

  private func fill(for cell: HabitHeatmapModel.Cell) -> AnyShapeStyle {
    guard cell.intensity != .absent else { return AnyShapeStyle(Color.clear) }
    return fill(forLevel: cell.level)
  }

  /// The graded accent ramp: level 0 (no activity) is a neutral quaternary wash;
  /// levels 1…4 step up the environment `.tint` (the app accent) opacity to a
  /// full-accent "met" cell. Opacity steps keep the ramp derived from the accent
  /// token and correct in light and dark rather than hardcoding shades.
  private func fill(forLevel level: Int) -> AnyShapeStyle {
    switch level {
    case ...0: return AnyShapeStyle(.quaternary)
    case 1: return AnyShapeStyle(.tint.opacity(0.28))
    case 2: return AnyShapeStyle(.tint.opacity(0.5))
    case 3: return AnyShapeStyle(.tint.opacity(0.72))
    default: return AnyShapeStyle(.tint)
    }
  }

  // MARK: Legend

  private var legend: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("habits.heatmap.legend.less", defaultValue: "Less", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      ForEach(0...4, id: \.self) { level in
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
          .fill(fill(forLevel: level))
          .frame(width: cellSize, height: cellSize)
      }
      Text(LocalizedStringResource("habits.heatmap.legend.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
    }
    .accessibilityHidden(true)
  }

  // MARK: Computation

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
    detail: AppStore.HabitDetail?,
    weeks: Int,
    calendar: Calendar
  ) -> HabitHeatmapModel.Grid {
    guard let detail else { return .empty }
    return HabitHeatmapModel.makeGrid(
      completions: detail.completions.completions,
      targetCount: habit.targetCount,
      weeks: weeks,
      endDate: Date(),
      calendar: calendar
    )
  }

  private func heatmapAccessibilityLabel(grid: HabitHeatmapModel.Grid) -> String {
    var met = 0
    var partial = 0
    for column in grid.columns {
      for cell in column {
        switch cell.intensity {
        case .met: met += 1
        case .partial: partial += 1
        case .none, .absent: break
        }
      }
    }
    return String(
      format: String(
        localized: "habits.heatmap.summary_a11y",
        defaultValue: "Completion heatmap for the last %lld weeks: %lld days met target, %lld partial days",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      weeks,
      met,
      partial
    )
  }
}
