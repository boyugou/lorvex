import CoreGraphics
import Testing

@testable import LorvexApple

// While a block is dragged on the week grid it reads the time its release
// would give it, from the same geometry the release uses.

private let hourHeight: CGFloat = 48
private let nineToTen = 9 * 60..<10 * 60

private func draft(
  _ kind: CalendarWeekGridView.RescheduleDraft.Kind, dx: CGFloat = 0, dy: CGFloat
) -> CalendarWeekGridView.RescheduleDraft {
  CalendarWeekGridView.RescheduleDraft(
    blockID: "block", kind: kind, translation: CGSize(width: dx, height: dy), columnWidth: 100)
}

private func landed(
  _ draft: CalendarWeekGridView.RescheduleDraft, of time: Range<Int> = nineToTen,
  minimumLength: Int = 15
) -> Range<Int> {
  draft.landedTime(of: time, hourHeight: hourHeight, minimumLength: minimumLength)
}

@Test
func aMovedBlockReadsItsNewStartAndKeepsItsLength() {
  #expect(landed(draft(.move, dy: 48)) == 10 * 60..<11 * 60)
  #expect(landed(draft(.move, dy: -24)) == 8 * 60 + 30..<9 * 60 + 30)
}

@Test
func aMovedBlockReadsTheQuarterHourItWouldSnapTo() {
  #expect(landed(draft(.move, dy: 20)) == 9 * 60 + 15..<10 * 60 + 15)
  #expect(landed(draft(.move, dy: 8)) == nineToTen)
}

@Test
func aMovedBlockIgnoresHorizontalTravelAndStaysInTheDay() {
  #expect(landed(draft(.move, dx: 250, dy: 0)) == nineToTen)
  #expect(landed(draft(.move, dy: 4_000), of: 23 * 60..<24 * 60) == 23 * 60..<24 * 60)
  #expect(landed(draft(.move, dy: -4_000)) == 0..<60)
}

@Test
func aBottomResizeReadsTheNewEnd() {
  #expect(landed(draft(.resize, dy: 24)) == 9 * 60..<10 * 60 + 30)
  #expect(landed(draft(.resize, dy: -4_000)) == 9 * 60..<9 * 60 + 15)
}

@Test
func aTopResizeReadsTheNewStart() {
  #expect(landed(draft(.resizeTop, dy: -24)) == 8 * 60 + 30..<10 * 60)
  #expect(landed(draft(.resizeTop, dy: 4_000)) == 9 * 60 + 45..<10 * 60)
}

@Test
func aResizeStopsAtTheMinimumLengthItIsGiven() {
  #expect(landed(draft(.resize, dy: -4_000), minimumLength: 20) == 9 * 60..<9 * 60 + 20)
  #expect(landed(draft(.resizeTop, dy: 4_000), minimumLength: 20) == 9 * 60 + 40..<10 * 60)
}
