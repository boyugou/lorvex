import CoreGraphics
import Testing

@testable import LorvexApple

/// Today on macOS divides the width right of the sidebar between its column
/// and the day rail by ``TodayPageLayout``'s rules.
private func layout(
  _ areaWidth: CGFloat, inspectorOpen: Bool = false,
  before placement: TodaySchedulePlacement? = nil
) -> TodayPageLayout {
  TodayPageLayout.resolve(
    areaWidth: areaWidth, inspectorOpen: inspectorOpen, placementBeforeInspector: placement)
}

private func rail(_ width: CGFloat, shown: Bool = true) -> TodayPageLayout {
  TodayPageLayout(schedulePlacement: .besideColumn, railWidth: width, showsRail: shown)
}

@Test
func todayKeepsTheScheduleInTheColumnWhenTheRailDoesNotFit() {
  #expect(layout(TodayPageMetrics.railThreshold - 1) == .columnOnly)
}

@Test
func todayGivesTheRailTheWidthTheFullColumnLeaves() {
  // At the narrowest area the rail holds its minimum and the column gives way.
  #expect(layout(TodayPageMetrics.railThreshold) == rail(TodayPageMetrics.railMinWidth))
  // Past the full column, the spare width goes to the rail, up to its maximum.
  #expect(layout(TodayPageMetrics.columnFullWidth + 400) == rail(400))
  #expect(layout(TodayPageMetrics.columnFullWidth + 2_000) == rail(TodayPageMetrics.railMaxWidth))
}

@Test
func todayInspectorTakesTheRailsPlaceUnlessAllThreePanesFit() {
  let threePanes =
    TodayPageMetrics.columnFullWidth + TodayPageMetrics.railMinWidth
    + MainWindowLayoutMetrics.inspectorIdealWidth
  // The column keeps every task while the inspector stands where the rail
  // was, and the rail keeps, off screen, the width it returns to.
  let hidden = layout(threePanes - 1, inspectorOpen: true, before: .besideColumn)
  #expect(hidden == rail(layout(threePanes - 1).railWidth ?? 0, shown: false))
  #expect(hidden.railWidth == TodayPageMetrics.railMaxWidth)
  #expect(
    layout(threePanes, inspectorOpen: true, before: .besideColumn)
      == rail(TodayPageMetrics.railMinWidth))
}

@Test
func todayKeepsItsPlacementWhileTheInspectorIsOpen() {
  // A narrow window grows to fit the inspector; the growth alone would fit
  // the rail, and must not move the schedule out of the column.
  let grown = TodayPageMetrics.railThreshold + 300
  #expect(layout(grown, inspectorOpen: true, before: .inColumn) == .columnOnly)
  // Closing the inspector lets the page decide by its width again.
  #expect(layout(grown, inspectorOpen: false, before: .inColumn).schedulePlacement == .besideColumn)
  // A page that first appears with the inspector open takes the placement
  // its width fits, which it then keeps.
  #expect(layout(grown, inspectorOpen: true).schedulePlacement == .besideColumn)
  #expect(layout(TodayPageMetrics.railThreshold - 1, inspectorOpen: true) == .columnOnly)
}
