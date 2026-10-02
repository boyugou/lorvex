import Testing

@testable import LorvexWidgetViews

/// Where the small widget's two-line label may start its second line: only at
/// a space, so a Korean particle stays with the time before it.
struct WidgetSpaceWrappedTextTests {
  private typealias Cut = WidgetSpaceWrappedText.Cut

  @Test("A label is cut at its spaces, the last space first")
  func cutsAtSpacesLastFirst() {
    #expect(WidgetSpaceWrappedText.cuts(of: "오전 10:30까지") == [Cut(head: "오전", tail: "10:30까지")])
    #expect(
      WidgetSpaceWrappedText.cuts(of: "上午 10:30 結束") == [
        Cut(head: "上午 10:30", tail: "結束"), Cut(head: "上午", tail: "10:30 結束"),
      ])
  }

  @Test("No-break spaces and space-less text offer no cut")
  func noBreakSpacesAreNotCut() {
    #expect(WidgetSpaceWrappedText.cuts(of: "9時45分～10時30分").isEmpty)
    #expect(WidgetSpaceWrappedText.cuts(of: "10:30\u{00A0}AM").isEmpty)
    #expect(
      WidgetSpaceWrappedText.cuts(of: "Until 10:30\u{202F}AM") == [
        Cut(head: "Until", tail: "10:30\u{202F}AM")
      ])
  }
}
