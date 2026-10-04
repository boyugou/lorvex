#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import LorvexCore

  /// `lorvexLineClamp` tells a "Show more" control whether the line limit hides
  /// any text at the width the text is laid out in. These tests host the view
  /// in an offscreen window and read the answer after layout.
  @Suite("Line clamp")
  @MainActor
  struct LorvexLineClampTests {
    private static let briefing =
      "The offsite agenda comes first: the venue can't be booked until it's settled, "
      + "so I moved the booking to tomorrow. Two meetings this afternoon."

    private final class Reading {
      var hidesText = false
    }

    private struct Probe: View {
      let text: String
      let lines: Int
      let isClamped: Bool
      let width: CGFloat
      let reading: Reading
      @State private var hidesText = false

      var body: some View {
        Text(verbatim: text)
          .font(LorvexDesign.Typography.briefing)
          .lorvexLineClamp(lines, isClamped: isClamped, hidesText: $hidesText)
          .frame(width: width, alignment: .topLeading)
          .onChange(of: hidesText) { _, value in reading.hidesText = value }
      }
    }

    /// What the modifier reports for `text` laid out `width` points wide.
    private func hidesText(_ text: String, lines: Int, width: CGFloat, isClamped: Bool = true) -> Bool {
      let reading = Reading()
      let hosting = NSHostingView(
        rootView: Probe(text: text, lines: lines, isClamped: isClamped, width: width, reading: reading))
      let size = hosting.fittingSize
      let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      hosting.frame = NSRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()
      // The measurements are read after layout and land in state a turn later.
      for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      window.contentView = nil
      return reading.hidesText
    }

    @Test("a text that fits within the limit hides nothing")
    func fittingTextHidesNothing() {
      #expect(!hidesText("Two meetings this afternoon.", lines: 3, width: 600))
      #expect(!hidesText(Self.briefing, lines: 3, width: 700))
    }

    @Test("a text taller than the limit reports hidden lines")
    func tallTextHidesLines() {
      #expect(hidesText(Self.briefing, lines: 3, width: 180))
      #expect(hidesText(Self.briefing, lines: 1, width: 700))
    }

    @Test("the answer follows the width: wide enough to fit, narrow enough to cut")
    func answerFollowsTheWidth() {
      var answers: [Bool] = []
      for width in stride(from: 700.0, through: 160.0, by: -20.0) {
        answers.append(hidesText(Self.briefing, lines: 3, width: CGFloat(width)))
      }
      #expect(answers.first == false)
      #expect(answers.last == true)
      // Narrowing never un-hides lines: once the limit cuts, it keeps cutting.
      if let firstCut = answers.firstIndex(of: true) {
        #expect(answers[firstCut...].allSatisfy { $0 })
      }
    }

    @Test("opening the text does not change what is reported")
    func answerIgnoresTheClampState() {
      #expect(hidesText(Self.briefing, lines: 3, width: 180, isClamped: false))
      #expect(!hidesText("Two meetings this afternoon.", lines: 3, width: 600, isClamped: false))
    }
  }
#endif

/// Both Today surfaces decide whether to offer "Show more" by measuring the
/// text, never by counting its characters, which misjudges every width but
/// one.
@Suite("Briefing fold")
struct BriefingFoldSourceTests {
  private var packageRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  @Test("the Mac and iOS briefings fold through the measured line clamp")
  func briefingsMeasureTheirText() throws {
    for path in ["Sources/LorvexApple/Views/TodayColumn.swift", "Sources/LorvexMobile/MobileTodayPage.swift"] {
      let source = try String(contentsOf: packageRoot.appending(path: path), encoding: .utf8)
      #expect(source.contains(".lorvexLineClamp("), "\(path)")
      #expect(source.contains("if briefingHidesText {"), "\(path)")
      #expect(!source.contains("briefingFoldLength"), "\(path)")
      #expect(!source.contains("text.count >"), "\(path)")
    }
  }
}
