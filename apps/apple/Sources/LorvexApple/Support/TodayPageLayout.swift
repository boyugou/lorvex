import CoreGraphics
import LorvexCore

/// The widths Today's page is built from.
enum TodayPageMetrics {
  /// The widest the column's text runs.
  static let columnMaxWidth: CGFloat = 720
  /// The narrowest column a rail may leave beside it: room for a task row's
  /// circle, its title, and a metadata line of a time, a list and a due date.
  static let columnMinWidth: CGFloat = 480
  /// The narrowest and the widest the day rail is drawn. At its narrowest it
  /// is as wide as the inspector opens, so the inspector takes its place
  /// without moving the column.
  static let railMinWidth: CGFloat = MainWindowLayoutMetrics.inspectorIdealWidth
  static let railMaxWidth: CGFloat = 460

  /// The column's leading inset, which puts its date line on the edge every
  /// workspace title starts from.
  static let columnLeadingInset = WorkspaceHeaderTitleMetrics.titleInset
  /// The column's trailing inset beside the rail, where a divider already
  /// separates the two; with the schedule in the column it matches the
  /// leading inset.
  static let columnTrailingInsetBesideRail = LorvexDesign.Spacing.xl

  /// The column at its full text width beside the rail, insets included.
  static let columnFullWidth = columnLeadingInset + columnMaxWidth + columnTrailingInsetBesideRail
  /// The narrowest area that holds the narrowest column and the narrowest rail.
  static let railThreshold =
    columnLeadingInset + columnMinWidth + columnTrailingInsetBesideRail + railMinWidth
}

/// How Today divides the width it is given: one column that holds the day's
/// schedule above its tasks, or a column that lists every task with the day
/// on a time grid in a rail beside it.
///
/// The rail stands when the area right of the sidebar fits the narrowest
/// column and the narrowest rail. Opening the inspector never moves the
/// schedule between the column and the rail, which would reorder the rows
/// under the pointer: the page keeps the placement it had before the
/// inspector opened, whatever the window does to make room for it, and
/// decides again when the inspector closes.
///
/// While the inspector is open beside a column that lists every task, the
/// rail is on screen only if all three panes fit with the column at its full
/// width. Otherwise the inspector stands in the rail's place: the column
/// keeps its rows, and the rail keeps its width and its place on the time
/// axis off screen, so it returns as it was when the inspector closes.
struct TodayPageLayout: Equatable {
  let schedulePlacement: TodaySchedulePlacement
  /// The rail's width while the schedule stands beside the column, on screen
  /// or not; nil with the schedule in the column.
  let railWidth: CGFloat?
  /// Whether the rail is on screen.
  let showsRail: Bool

  /// The schedule in the column and no rail.
  static let columnOnly = TodayPageLayout(
    schedulePlacement: .inColumn, railWidth: nil, showsRail: false)

  /// - Parameters:
  ///   - areaWidth: the width right of the sidebar, the inspector included.
  ///   - inspectorOpen: whether the window's inspector takes part of it.
  ///   - placementBeforeInspector: the placement the page last had, which it
  ///     keeps while the inspector is open; nil when the page first appears,
  ///     where it takes the placement its width fits.
  static func resolve(
    areaWidth: CGFloat, inspectorOpen: Bool,
    placementBeforeInspector: TodaySchedulePlacement? = nil
  ) -> TodayPageLayout {
    let fitted: TodaySchedulePlacement =
      areaWidth >= TodayPageMetrics.railThreshold ? .besideColumn : .inColumn
    let placement = inspectorOpen ? placementBeforeInspector ?? fitted : fitted
    guard placement == .besideColumn else { return .columnOnly }
    // The width the rail has without the inspector, which it keeps off screen.
    let restingWidth = railWidth(besideFullColumnIn: areaWidth)
    guard inspectorOpen else {
      return TodayPageLayout(schedulePlacement: .besideColumn, railWidth: restingWidth, showsRail: true)
    }
    let room = areaWidth - MainWindowLayoutMetrics.inspectorIdealWidth
    guard room - TodayPageMetrics.columnFullWidth >= TodayPageMetrics.railMinWidth else {
      return TodayPageLayout(schedulePlacement: .besideColumn, railWidth: restingWidth, showsRail: false)
    }
    return TodayPageLayout(
      schedulePlacement: .besideColumn, railWidth: railWidth(besideFullColumnIn: room), showsRail: true)
  }

  /// What `room` leaves beside the column at its full width, held between the
  /// rail's narrowest and widest.
  private static func railWidth(besideFullColumnIn room: CGFloat) -> CGFloat {
    min(
      max(room - TodayPageMetrics.columnFullWidth, TodayPageMetrics.railMinWidth),
      TodayPageMetrics.railMaxWidth)
  }
}
