#if os(macOS)
  import AppKit
  import LorvexCore
  import SwiftUI
  import Testing

  /// A grid block's text arranges itself inside the room the block gives it:
  /// whatever the block's height and width, the title's script, or whether it
  /// wraps, the arrangement drawn asks for no more height than the block has,
  /// so no line is cut off at the block's bottom edge. Devanagari stands in for
  /// the scripts whose lines run taller than Latin.
  @MainActor
  @Test(arguments: [CGFloat(60), 110, 200])
  func calendarBlockTextNeverOutgrowsItsBlock(width: CGFloat) {
    let titles = [
      "Team standup",
      "Draft the team offsite agenda before Friday",
      "टीम स्टैंडअप बैठक",
      "शुक्रवार से पहले टीम ऑफ़साइट का एजेंडा तैयार करें",
    ]
    let times: [(time: String?, range: String?)] = [
      ("9:30 AM", "9:30 – 9:45 AM"), ("पू 9:30", "पू 9:30–9:45"), (nil, nil),
    ]
    for height in [CGFloat(12), 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 60] {
      for title in titles {
        for sample in times {
          let event = LorvexCalendarBlockText(title: title, time: sample.time, range: sample.range)
          let task = LorvexCalendarBlockText(title: title, time: sample.time, range: sample.range) {
            Image(systemName: "circle").font(LorvexDesign.Typography.tertiaryText).frame(width: 16)
          }
          let proposal = CGSize(width: width, height: height)
          let eventHeight = NSHostingController(rootView: event).sizeThatFits(in: proposal).height
          let taskHeight = NSHostingController(rootView: task).sizeThatFits(in: proposal).height
          #expect(
            eventHeight <= height,
            "\(title) / \(sample.time ?? "no time") in \(width)×\(height) asks for \(eventHeight)")
          #expect(
            taskHeight <= height,
            "\(title) / \(sample.time ?? "no time") beside a circle in \(width)×\(height) asks for \(taskHeight)")
        }
      }
    }
  }
#endif
