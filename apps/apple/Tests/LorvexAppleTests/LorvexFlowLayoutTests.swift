import LorvexCore
import SwiftUI
import Testing

/// `LorvexFlowLayout` sizing, measured by rendering the layout through
/// `ImageRenderer` at a proposed width and reading the image's size.
@MainActor
@Suite("Flow layout")
struct LorvexFlowLayoutTests {
  private func renderedSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    return renderer.nsImage?.size ?? .zero
  }

  @Test("A child wider than a whole line wraps inside the line")
  func oversizedChildWrapsInsideTheLine() {
    let tags = Text("urgent · work · research · home · engineering · someday")
      .fixedSize(horizontal: false, vertical: true)
    let oneLine = renderedSize(tags, width: 2000)
    let wrapped = renderedSize(LorvexFlowLayout(spacing: 0, lineSpacing: 0) { tags }, width: 120)

    #expect(oneLine.width > 120)
    #expect(wrapped.width <= 120)
    #expect(wrapped.height > oneLine.height)
  }

  @Test("A child that wraps gets its rows to itself")
  func wrappedChildTakesItsRowsAlone() {
    let text = Text("Wednesday afternoon at").fixedSize(horizontal: false, vertical: true)
    let dot = Color.clear.frame(width: 4, height: 4)
    // Just narrower than the text, so only its last word wraps and a dot
    // would fit beside the wrapped block.
    let lineWidth = (renderedSize(text, width: 2000).width - 4).rounded(.down)
    let wrapped = renderedSize(LorvexFlowLayout(spacing: 0, lineSpacing: 0) { text }, width: lineWidth)
    let flow = renderedSize(
      LorvexFlowLayout(spacing: 0, lineSpacing: 0) { dot; text; dot }, width: lineWidth)

    #expect(wrapped.width + 4 <= lineWidth)
    #expect(flow.height == 4 + wrapped.height + 4)
  }

  @Test("Children that fit keep their ideal size and share a line")
  func fittingChildrenShareALine() {
    let chip = Text("Today").fixedSize()
    let single = renderedSize(chip, width: 300)
    let pair = renderedSize(LorvexFlowLayout(spacing: 8, lineSpacing: 8) { chip; chip }, width: 300)

    #expect(pair.width == single.width * 2 + 8)
    #expect(pair.height == single.height)
  }

  @Test("fillsWidth claims the offered width; by default the layout hugs its longest line")
  func fillsWidthClaimsTheOfferedWidth() {
    let chip = Text("Today").fixedSize()

    #expect(renderedSize(LorvexFlowLayout(fillsWidth: true) { chip }, width: 300).width == 300)
    #expect(renderedSize(LorvexFlowLayout { chip }, width: 300).width < 300)
  }
}
