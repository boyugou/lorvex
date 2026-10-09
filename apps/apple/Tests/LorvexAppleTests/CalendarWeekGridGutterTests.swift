#if os(macOS)
  import AppKit
  import LorvexCore
  import SwiftUI
  import Testing

  @testable import LorvexApple

  /// The header, the all-day strip and the hour gutter of the calendar grid
  /// share one gutter width. It fits the widest hour label and the widest word
  /// of the all-day label, each on one line.
  @MainActor
  @Suite struct CalendarWeekGridGutterTests {
    private static let englishHourLabels = ["12 AM", "10 AM", "11 PM"]

    /// The width of `text` on one line in the gutter's font, as SwiftUI lays it out.
    private static func lineWidth(_ text: String) -> CGFloat {
      NSHostingController(rootView: Text(text).font(LorvexDesign.Typography.tertiaryText))
        .sizeThatFits(in: CGSize(width: 10_000, height: 1_000)).width
    }

    /// English asks for nothing beyond the stock width, so its grid does not move.
    @Test func englishLabelsKeepTheStockGutter() {
      let fitted = CalendarWeekGridMetrics.gutterWidth(
        fittingHourLabels: Self.englishHourLabels, allDayLabel: "all-day")
      #expect(fitted == CalendarWeekGridMetrics.gutterWidth)
    }

    /// The all-day label's frame is the gutter less the inset and the label wraps
    /// between words, so the widest word on one line must fit that frame: a word
    /// wider than it would break inside itself.
    @Test(arguments: [
      "all-day", "ganztägig", "seharian", "giornata", "journée", "todo el día", "весь день", "முழு நாளும்",
      "تمام\u{200C}روز", "終日",
    ])
    func gutterHoldsTheWidestWordOfTheAllDayLabel(label: String) {
      let gutter = CalendarWeekGridMetrics.gutterWidth(
        fittingHourLabels: Self.englishHourLabels, allDayLabel: label)
      let widest = label.split(whereSeparator: \.isWhitespace).map { Self.lineWidth(String($0)) }.max() ?? 0
      let frame = gutter - CalendarWeekGridMetrics.gutterLabelInset
      #expect(widest <= frame, "\(label) needs \(widest) pt in a \(frame) pt label frame")
    }

    /// A label of several short words is measured by its widest word, not its
    /// whole width, since it wraps between the words.
    @Test func aWrappingLabelIsMeasuredByItsWidestWord() {
      let label = "todo el día"
      let frame = CalendarWeekGridMetrics.gutterWidth - CalendarWeekGridMetrics.gutterLabelInset
      #expect(Self.lineWidth(label) > frame)
      let fitted = CalendarWeekGridMetrics.gutterWidth(
        fittingHourLabels: Self.englishHourLabels, allDayLabel: label)
      #expect(fitted == CalendarWeekGridMetrics.gutterWidth)
    }
  }
#endif
