import CoreGraphics
import Testing

@testable import LorvexApple

/// The week grid's time axis opens on its anchor hour and follows that hour
/// until the person scrolls.
@Test
func timeAxisStopsOnTheAnchorHourOrTheLastWholeHourItCanReach() {
  let hour: CGFloat = 48
  #expect(CalendarTimeAxisGeometry.offset(forHour: 9, hourHeight: hour, scrollableHeight: 600) == 432)
  // 340 pt of scrolling reaches 7 AM whole; 10 AM would stop part-way through an hour.
  #expect(CalendarTimeAxisGeometry.offset(forHour: 10, hourHeight: hour, scrollableHeight: 340) == 336)
  #expect(CalendarTimeAxisGeometry.offset(forHour: 10, hourHeight: hour, scrollableHeight: 0) == 0)
  #expect(CalendarTimeAxisGeometry.offset(forHour: -1, hourHeight: hour, scrollableHeight: 600) == 0)
  #expect(CalendarTimeAxisGeometry.offset(forHour: 3, hourHeight: 0, scrollableHeight: 600) == 0)
}

private let hourHeight: CGFloat = 48

private func axis(_ scrollableHeight: CGFloat, at offset: CGFloat) -> CalendarTimeAxisGeometry {
  CalendarTimeAxisGeometry(scrollableHeight: scrollableHeight, offset: offset)
}

private func request(_ offset: CGFloat, animated: Bool = false) -> CalendarTimeAxisTracker.Request {
  CalendarTimeAxisTracker.Request(offset: offset, isAnimated: animated)
}

/// A tracker whose grid opened on 9 AM (offset 432) with 600 pt to scroll.
@MainActor
private func placedTracker() -> CalendarTimeAxisTracker {
  let tracker = CalendarTimeAxisTracker()
  _ = tracker.geometryChanged(to: axis(600, at: 0), anchorHour: 9, hourHeight: hourHeight)
  _ = tracker.geometryChanged(to: axis(600, at: 432), anchorHour: 9, hourHeight: hourHeight)
  return tracker
}

@MainActor
@Test
func timeAxisAsksAgainAfterEachReportUntilItIsSeenOnTheAnchorHour() {
  let tracker = CalendarTimeAxisTracker()
  // A scroll view without a size has nothing to scroll.
  #expect(tracker.geometryChanged(to: axis(0, at: 0), anchorHour: 9, hourHeight: hourHeight) == nil)
  #expect(tracker.isPlacing)

  // A window reports a size that does not hold, then the one that does. The
  // request made for the first is dropped, so each report gets its own.
  #expect(
    tracker.geometryChanged(to: axis(1_089, at: 0), anchorHour: 9, hourHeight: hourHeight)
      == request(432))
  #expect(
    tracker.geometryChanged(to: axis(600, at: 0), anchorHour: 9, hourHeight: hourHeight)
      == request(432))
  #expect(!tracker.isWherePlaced)

  // The report that shows the axis on the hour ends the placement.
  #expect(tracker.geometryChanged(to: axis(600, at: 432.4), anchorHour: 9, hourHeight: hourHeight) == nil)
  #expect(!tracker.isPlacing)
  #expect(tracker.isWherePlaced)
}

@MainActor
@Test
func timeAxisStopsAskingForAPlacementThatNeverLands() {
  let tracker = CalendarTimeAxisTracker()
  for step in 0..<CalendarTimeAxisTracker.requestBudget {
    // Each report differs, as a real one does, and none shows the axis moved.
    #expect(
      tracker.geometryChanged(
        to: axis(600 + CGFloat(step), at: 0), anchorHour: 9, hourHeight: hourHeight) == request(432))
  }
  #expect(tracker.geometryChanged(to: axis(700, at: 0), anchorHour: 9, hourHeight: hourHeight) == nil)
  #expect(!tracker.isPlacing)
  #expect(!tracker.isWherePlaced)
}

@MainActor
@Test
func timeAxisFollowsTheAnchorUntilThePersonScrolls() {
  let tracker = placedTracker()
  // The clock passes an hour under an axis the grid placed: it follows, and
  // the person sees it move.
  #expect(tracker.anchorMoved(toHour: 10, hourHeight: hourHeight) == request(480, animated: true))
  _ = tracker.geometryChanged(to: axis(600, at: 480), anchorHour: 10, hourHeight: hourHeight)
  #expect(tracker.isWherePlaced)

  // The person scrolls, and the axis is theirs.
  tracker.personScrolled()
  _ = tracker.geometryChanged(to: axis(600, at: 200), anchorHour: 10, hourHeight: hourHeight)
  #expect(tracker.anchorMoved(toHour: 11, hourHeight: hourHeight) == nil)

  // Another range of days puts it on the anchor hour wherever it stands, and
  // from there it follows the anchor again.
  #expect(tracker.rangeChanged(anchorHour: 8, hourHeight: hourHeight) == request(384, animated: true))
  _ = tracker.geometryChanged(to: axis(600, at: 384), anchorHour: 8, hourHeight: hourHeight)
  #expect(tracker.anchorMoved(toHour: 9, hourHeight: hourHeight) == request(432, animated: true))
  // An axis already on the hour is not asked to scroll.
  _ = tracker.geometryChanged(to: axis(600, at: 432), anchorHour: 9, hourHeight: hourHeight)
  #expect(tracker.rangeChanged(anchorHour: 9, hourHeight: hourHeight) == nil)
}

@MainActor
@Test
func timeAxisIsPlacedAgainWhenItsSizeChangesUnderAnAxisThePersonHasNotScrolled() {
  // The grid opened while only 340 pt could scroll, which reaches 7 AM, not
  // the 9 AM anchor.
  let tracker = CalendarTimeAxisTracker()
  _ = tracker.geometryChanged(to: axis(340, at: 0), anchorHour: 9, hourHeight: hourHeight)
  #expect(tracker.geometryChanged(to: axis(340, at: 336), anchorHour: 9, hourHeight: hourHeight) == nil)
  #expect(!tracker.isPlacing)

  // The size that holds can reach 9 AM, so the axis goes there.
  #expect(
    tracker.geometryChanged(to: axis(600, at: 336), anchorHour: 9, hourHeight: hourHeight)
      == request(432))
  #expect(tracker.geometryChanged(to: axis(600, at: 432), anchorHour: 9, hourHeight: hourHeight) == nil)

  // A resize that leaves the hour reachable asks for nothing.
  #expect(tracker.geometryChanged(to: axis(640, at: 432), anchorHour: 9, hourHeight: hourHeight) == nil)
  #expect(!tracker.isPlacing)

  // After the person scrolls, a new size leaves the axis where they put it.
  tracker.personScrolled()
  _ = tracker.geometryChanged(to: axis(640, at: 100), anchorHour: 9, hourHeight: hourHeight)
  #expect(tracker.geometryChanged(to: axis(300, at: 100), anchorHour: 9, hourHeight: hourHeight) == nil)
}

@MainActor
@Test
func timeAxisPlacementThatStoppedShortRestartsWhenTheAnchorOrTheRangeChanges() {
  // The opening request was dropped and no report followed it.
  let tracker = CalendarTimeAxisTracker()
  #expect(
    tracker.geometryChanged(to: axis(600, at: 0), anchorHour: 9, hourHeight: hourHeight)
      == request(432))
  #expect(tracker.isPlacing)

  // The day's blocks load and move the anchor: the grid asks for the new
  // hour without animation and without spending the placement's requests.
  #expect(tracker.anchorMoved(toHour: 7, hourHeight: hourHeight) == request(336))
  #expect(tracker.rangeChanged(anchorHour: 7, hourHeight: hourHeight) == request(336))
  #expect(tracker.isPlacing)
  #expect(tracker.geometryChanged(to: axis(600, at: 336), anchorHour: 7, hourHeight: hourHeight) == nil)
  #expect(!tracker.isPlacing)
  #expect(tracker.isWherePlaced)
}
