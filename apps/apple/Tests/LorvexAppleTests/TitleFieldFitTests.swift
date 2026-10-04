#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import LorvexCore

  /// A wrapped `TextField(axis: .vertical)` on macOS is an `NSTextField`
  /// whose frame SwiftUI rounds to the nearest point. When a font's line
  /// metrics leave the cell's required height a hair above the rounded frame,
  /// AppKit does not draw the last line, so part of the user's text vanishes.
  /// These tests hold the fonts of the app's multi-line fields to a frame at
  /// least as tall as the text needs, at every width and line count scanned.
  @Suite("Wrapped text field height")
  @MainActor
  struct TitleFieldFitTests {
    private static let words =
      "Practice the piano scales and arpeggios for at least twenty minutes and then some "
      + "more words so the text wraps onto many lines in a narrow column"

    private func wrappingField(in view: NSView) -> NSTextField? {
      if let field = view as? NSTextField, field.cell?.wraps == true,
        !type(of: field).description().contains("SimpleLabel")
      {
        return field
      }
      for subview in view.subviews {
        if let found = wrappingField(in: subview) { return found }
      }
      return nil
    }

    /// The widest shortfall, in points, between the height the field's cell
    /// needs and the height SwiftUI gave the field, over widths from 150 to
    /// 260 points; zero when the frame always covers the text.
    private func worstShortfall(font: Font) -> CGFloat {
      var worst: CGFloat = 0
      for width in stride(from: 150.0, through: 260.0, by: 2.0) {
        let length = Int(width) / 2 + 20
        let content = TextField("Title", text: .constant(String(Self.words.prefix(length))), axis: .vertical)
          .font(font)
          .textFieldStyle(.plain)
          .lineLimit(1...)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: CGFloat(width))
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        let window = NSWindow(
          contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        guard let field = wrappingField(in: hosting) else { continue }
        let needed =
          field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: field.frame.width, height: 10_000)).height ?? 0
        worst = max(worst, needed - field.frame.height)
      }
      return worst
    }

    @Test("the detail title face never leaves a wrapped line undrawn")
    func detailTitle() {
      #expect(worstShortfall(font: LorvexDesign.Typography.detailTitle) <= 0.001)
    }

    @Test("the other multi-line field faces never leave a wrapped line undrawn")
    func bodyFaces() {
      #expect(worstShortfall(font: LorvexDesign.Typography.primaryText) <= 0.001)
      #expect(worstShortfall(font: LorvexDesign.Typography.secondaryText) <= 0.001)
      #expect(worstShortfall(font: LorvexDesign.Typography.secondaryText.italic()) <= 0.001)
    }

    @Test("the check detects the shortfall the .title2 text style causes")
    func checkCatchesTitle2() {
      #expect(worstShortfall(font: .system(.title2, design: .default).weight(.semibold)) > 0.001)
    }
  }
#endif
