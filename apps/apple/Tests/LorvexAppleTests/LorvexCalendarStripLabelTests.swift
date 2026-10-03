#if os(macOS)
  import AppKit
  import LorvexCore
  import SwiftUI
  import Testing

  @MainActor
  private func fittedSize(_ view: some View, width: CGFloat) -> CGSize {
    NSHostingController(rootView: view.font(LorvexDesign.Typography.tertiaryText))
      .sizeThatFits(in: CGSize(width: width, height: 1_000))
  }

  /// An all-day strip pill's text stays one line inside the width the pill
  /// gives it, whatever the title's length or script and whether a time joins
  /// it. Devanagari stands in for the scripts whose lines run taller than
  /// Latin.
  @MainActor
  @Test(arguments: [CGFloat(24), 60, 90, 140, 400])
  func calendarStripLabelStaysOneLineInsideItsWidth(width: CGFloat) {
    let titles = [
      "Gym", "Conference trip", "Quarterly planning offsite in Lisbon", "टीम ऑफ़साइट बैठक", "年度规划会议",
    ]
    for title in titles {
      for time in [nil, "7:00 PM", "Until 9:00 AM"] as [String?] {
        let label = fittedSize(LorvexCalendarStripLabel(title: title, time: time), width: width)
        let line = max(
          fittedSize(Text(title), width: 10_000).height,
          time.map { fittedSize(Text($0), width: 10_000).height } ?? 0)
        #expect(label.width <= width, "\(title) / \(time ?? "no time") in \(width) is \(label.width) wide")
        #expect(label.height <= line, "\(title) / \(time ?? "no time") in \(width) wraps to \(label.height)")
      }
    }
  }

  /// Where the title and the time both fit whole, the pill shows both, side
  /// by side.
  @MainActor
  @Test func calendarStripLabelShowsBothWholeWhereTheyFit() {
    let title = fittedSize(Text("Conference trip"), width: 10_000).width
    let time = fittedSize(Text("Until 9:00 AM").monospacedDigit(), width: 10_000).width
    let label = fittedSize(LorvexCalendarStripLabel(title: "Conference trip", time: "Until 9:00 AM"), width: 400)
    #expect(abs(label.width - (title + LorvexDesign.Spacing.xs + time)) < 1)
  }
#endif
