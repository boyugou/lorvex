import CoreGraphics
import Foundation
import Testing

@testable import LorvexCore

// The geometry behind dragging a block to another time or day and dropping a
// task on a day column. One point is one minute at 60 points per hour.

private let hour: CGFloat = 60

private func landing(
  start: Int = 9 * 60, duration: Int = 60, dx: CGFloat = 0, dy: CGFloat = 0,
  columnWidth: CGFloat = 100, dayIndex: Int = 2, dayCount: Int = 7
) -> CalendarGridMove.Landing {
  CalendarGridMove.landing(
    startMinute: start, duration: duration, translation: CGSize(width: dx, height: dy),
    hourHeight: hour, columnWidth: columnWidth, dayIndex: dayIndex, dayCount: dayCount)
}

@Test
func aDragShorterThanOneSnapStepChangesNothing() {
  #expect(landing(dy: 14).isUnchanged)
  #expect(landing(dy: -14).isUnchanged)
  #expect(landing(dy: 14).startMinute == 9 * 60)
}

@Test
func verticalTravelMovesTheStartInWholeQuarterHours() {
  #expect(landing(dy: 15).startMinute == 9 * 60 + 15)
  #expect(landing(dy: 29).startMinute == 9 * 60 + 15)
  #expect(landing(dy: 30).startMinute == 9 * 60 + 30)
  #expect(landing(dy: -15).startMinute == 9 * 60 - 15)
  #expect(landing(dy: -29).startMinute == 9 * 60 - 15)
  #expect(!landing(dy: 15).isUnchanged)
}

@Test
func aBlockKeepsItsOwnOffsetFromTheQuarterHour() {
  #expect(landing(start: 9 * 60 + 10, dy: 30).startMinute == 9 * 60 + 40)
}

@Test
func aMovedBlockStaysInsideTheDay() {
  #expect(landing(start: 30, dy: -600).startMinute == 0)
  #expect(landing(start: 22 * 60, duration: 90, dy: 600).startMinute == 24 * 60 - 90)
}

@Test
func horizontalTravelMovesToTheNearestColumnInsideTheVisibleOnes() {
  #expect(landing(dx: 49).dayShift == 0)
  #expect(landing(dx: 51).dayShift == 1)
  #expect(landing(dx: -151).dayShift == -2)
  #expect(landing(dx: 5_000).dayShift == 4, "day 2 of 7 stops at the last column")
  #expect(landing(dx: -5_000).dayShift == -2, "and at the first")
  #expect(!landing(dx: 51).isUnchanged)
}

@Test
func aDayColumnOfZeroWidthNeverMovesAcrossDays() {
  #expect(landing(dx: 400, columnWidth: 0).dayShift == 0)
}

@Test
func theMinuteUnderAPointStaysInsideTheDay() {
  #expect(CalendarGridMove.minute(atY: 0, hourHeight: hour) == 0)
  #expect(CalendarGridMove.minute(atY: 100, hourHeight: hour) == 100)
  #expect(CalendarGridMove.minute(atY: -40, hourHeight: hour) == 0)
  #expect(CalendarGridMove.minute(atY: 24 * 60 + 50, hourHeight: hour) == 24 * 60 - 1)
}

@Test
func aDropStartsOnTheQuarterHourAtOrBeforeThePointer() {
  #expect(CalendarGridMove.dropStart(atY: 600, hourHeight: hour, duration: 30) == 600)
  #expect(CalendarGridMove.dropStart(atY: 614, hourHeight: hour, duration: 30) == 600)
  #expect(CalendarGridMove.dropStart(atY: 615, hourHeight: hour, duration: 30) == 615)
}

@Test
func aDropEarlyEnoughToEndByMidnightKeepsTheBlockInTheDay() {
  #expect(CalendarGridMove.dropStart(atY: 24 * 60 - 1, hourHeight: hour, duration: 0) == 1425)
  #expect(CalendarGridMove.dropStart(atY: 24 * 60 - 1, hourHeight: hour, duration: 60) == 1380)
}

private let nineToTen = 9 * 60..<10 * 60

private func resized(
  _ edge: CalendarGridMove.Edge, of time: Range<Int> = nineToTen, dy: CGFloat,
  minimumLength: Int = CalendarGridMove.snapMinutes
) -> Range<Int> {
  CalendarGridMove.resized(
    time, edge: edge, translationHeight: dy, hourHeight: hour, minimumLength: minimumLength)
}

@Test
func draggingTheBottomEdgeMovesTheEndInWholeQuarterHours() {
  #expect(resized(.end, dy: 15) == 9 * 60..<10 * 60 + 15)
  #expect(resized(.end, dy: 29) == 9 * 60..<10 * 60 + 15)
  #expect(resized(.end, dy: 45) == 9 * 60..<10 * 60 + 45)
  #expect(resized(.end, dy: -15) == 9 * 60..<10 * 60 - 15)
  #expect(resized(.end, dy: -29) == 9 * 60..<10 * 60 - 15)
}

@Test
func draggingTheTopEdgeMovesTheStartInWholeQuarterHours() {
  #expect(resized(.start, dy: -30) == 8 * 60 + 30..<10 * 60)
  #expect(resized(.start, dy: 15) == 9 * 60 + 15..<10 * 60)
  #expect(resized(.start, dy: 29) == 9 * 60 + 15..<10 * 60)
}

@Test
func aResizeShorterThanOneSnapStepChangesNothing() {
  #expect(resized(.end, dy: 14) == nineToTen)
  #expect(resized(.start, dy: -14) == nineToTen)
}

@Test
func aShortDragLeavesABlockShorterThanTheMinimumAsItWas() {
  let tenMinutes = 9 * 60..<9 * 60 + 10
  #expect(resized(.end, of: tenMinutes, dy: 5, minimumLength: 20) == tenMinutes)
  #expect(resized(.start, of: tenMinutes, dy: -5, minimumLength: 20) == tenMinutes)
}

@Test
func aResizeStopsOneMinimumShortOfTheOppositeEdge() {
  #expect(resized(.end, dy: -600) == 9 * 60..<9 * 60 + 15)
  #expect(resized(.start, dy: 600) == 9 * 60 + 45..<10 * 60)
  #expect(resized(.end, dy: -600, minimumLength: 20) == 9 * 60..<9 * 60 + 20)
}

@Test
func aResizeStopsAtTheBoundsOfTheDay() {
  #expect(resized(.end, dy: 6_000) == 9 * 60..<24 * 60)
  #expect(resized(.start, dy: -6_000) == 0..<10 * 60)
  let lateBlock = 23 * 60 + 50..<24 * 60
  #expect(resized(.end, of: lateBlock, dy: 15) == lateBlock, "the block already ends at midnight")
  let lastQuarter = 23 * 60 + 45..<24 * 60
  #expect(resized(.end, of: lastQuarter, dy: -600) == lastQuarter, "and never drops below the minimum")
}

private func task(estimate: Int?, time: Range<Int>?) -> LorvexTask {
  LorvexTask(
    id: "t", title: "Write the brief", notes: "", priority: .p2, status: .open, dueDate: nil,
    plannedDate: Date(timeIntervalSince1970: 0), plannedTime: time, estimatedMinutes: estimate,
    tags: [])
}

@Test
func aTaskWithATimeKeepsItsLengthWhereverItStarts() {
  let planned = task(estimate: 120, time: 9 * 60..<9 * 60 + 45)
  #expect(planned.time(startingAt: 10 * 60 + 10) == 10 * 60 + 10..<10 * 60 + 55)
}

@Test
func aTaskWithoutATimeTakesItsEstimateOrHalfAnHour() {
  #expect(task(estimate: 90, time: nil).time(startingAt: 14 * 60) == 14 * 60..<15 * 60 + 30)
  #expect(task(estimate: nil, time: nil).time(startingAt: 14 * 60) == 14 * 60..<14 * 60 + 30)
}

@Test
func aTasksTimeNearMidnightIsHeldInsideTheDay() {
  #expect(task(estimate: 60, time: nil).time(startingAt: 23 * 60 + 50) == 23 * 60..<24 * 60)
}
