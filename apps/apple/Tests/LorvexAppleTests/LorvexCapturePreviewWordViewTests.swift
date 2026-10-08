import SwiftUI
import Testing

@testable import LorvexCore

/// How a capture preview's word fits a line, measured by rendering it through
/// `LorvexFlowLayout` at a proposed width with `ImageRenderer`.
@MainActor
@Suite("Capture preview word")
struct LorvexCapturePreviewWordViewTests {
  private func renderedSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.nsImage?.size ?? .zero
  }

  private func chip(_ label: String) -> LorvexCapturePreviewWordView {
    LorvexCapturePreviewWordView(
      word: .init(id: "list", label: label, role: .plain),
      horizontalPadding: 5, verticalPadding: 1, washOpacity: 0.1)
  }

  @Test("A word wider than its line shortens to one line of the line's width")
  func longWordShortensToTheLine() {
    let longName = "Cross-functional launch readiness with legal, security, support and regional marketing"
    let word = chip(longName)
    let ideal = renderedSize(word, width: 4000)
    let fitted = renderedSize(LorvexFlowLayout(spacing: 4, lineSpacing: 2) { word }, width: 200)

    #expect(ideal.width > 200)
    #expect(fitted.width <= 200)
    #expect(fitted.height == ideal.height)
  }

  @Test("A word that fits keeps its whole label")
  func shortWordKeepsItsWidth() {
    let word = chip("Tomorrow")
    let ideal = renderedSize(word, width: 4000)
    let fitted = renderedSize(LorvexFlowLayout(spacing: 4, lineSpacing: 2) { word }, width: 200)

    #expect(ideal.width < 200)
    #expect(fitted.width == ideal.width)
  }
}
