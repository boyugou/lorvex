import SwiftUI

/// A fold header's disclosure mark: a chevron pointing along the reading
/// direction while its section is folded and down while it is open, turning
/// between the two when the change animates. In a right-to-left layout the
/// folded chevron points left, the way the text runs, and the open one still
/// points down. Decorative and hidden from accessibility: the header button
/// carries the state. Style it as an image (`font`, `imageScale`,
/// `foregroundStyle`).
///
/// This is the one place a fold chevron is drawn, so every fold mirrors the
/// same way; the design-token gate rejects fixed left/right glyphs elsewhere.
public struct LorvexDisclosureChevron: View {
  let isExpanded: Bool

  public init(isExpanded: Bool) {
    self.isExpanded = isExpanded
  }

  public var body: some View {
    // The mirroring follows the rotation: the folded chevron flips to point
    // left, and the open one, already pointing down, flips onto itself.
    Image(systemName: "chevron.right")
      .rotationEffect(.degrees(isExpanded ? 90 : 0))
      .flipsForRightToLeftLayoutDirection(true)
      .accessibilityHidden(true)
  }
}

/// The filled part of a progress ring: an arc from twelve o'clock that runs
/// with the reading direction, clockwise in a left-to-right layout and
/// counterclockwise in a right-to-left one, the way the system's circular
/// gauges fill. Draw the ring's track under it as a plain stroked `Circle`,
/// which has no direction.
///
/// This is the one place a progress arc is drawn, so every ring fills the
/// same way; the design-token gate rejects `.trim(from:` elsewhere. A circle
/// trimmed and then turned with `rotationEffect` starts at six o'clock in a
/// right-to-left layout, because the layout mirrors the rotation's angle.
public struct LorvexProgressArc<Style: ShapeStyle>: View {
  let start: Double
  let end: Double
  let style: Style
  let lineWidth: CGFloat
  let lineCap: CGLineCap

  /// An arc over `fraction` of the ring, clamped to 0...1, with round ends.
  public init(fraction: Double, style: Style, lineWidth: CGFloat) {
    self.init(from: 0, to: fraction, style: style, lineWidth: lineWidth, lineCap: .round)
  }

  /// An arc from `start` to `end`, each a share of the ring (0...1) measured
  /// from twelve o'clock: one segment of a segmented ring.
  public init(from start: Double, to end: Double, style: Style, lineWidth: CGFloat, lineCap: CGLineCap) {
    self.start = start
    self.end = end
    self.style = style
    self.lineWidth = lineWidth
    self.lineCap = lineCap
  }

  public var body: some View {
    // The shape turns before it is trimmed, so the arc starts at twelve
    // o'clock in the shape's own space, which no layout mirrors; the flip then
    // mirrors the drawn arc in a right-to-left layout.
    Circle()
      .rotation(.degrees(-90))
      .trim(from: min(max(start, 0), 1), to: min(max(end, 0), 1))
      .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
      .flipsForRightToLeftLayoutDirection(true)
  }
}

// Keyboard shortcuts exist on the Mac and on an iPad or iPhone with a
// keyboard; watchOS has neither the keys nor the API.
#if os(macOS) || os(iOS)
  /// Which way a paging control moves through an ordered run of periods (days,
  /// weeks, months): backward to the earlier one, forward to the later one.
  public enum LorvexStepDirection: Sendable {
    case backward
    case forward

    /// The arrow key that points the way this step moves on screen. A
    /// left-to-right layout puts the earlier period on the left, so backward is
    /// the left arrow and forward the right arrow; a right-to-left layout
    /// mirrors the controls, and with them the keys.
    public func arrowKey(in layoutDirection: LayoutDirection) -> KeyEquivalent {
      let pointsRight = (self == .forward) == (layoutDirection == .leftToRight)
      return pointsRight ? .rightArrow : .leftArrow
    }
  }

  extension View {
    /// Binds ⌘ plus the arrow key that points the way this control steps
    /// (``LorvexStepDirection/arrowKey(in:)``), so the key always matches the
    /// chevron on screen: ⌘← for backward in a left-to-right layout, ⌘→ in a
    /// right-to-left one. `isEnabled` false binds nothing, for while a text
    /// field owns the arrow keys.
    public func lorvexStepShortcut(_ step: LorvexStepDirection, isEnabled: Bool = true) -> some View {
      modifier(LorvexStepShortcut(step: step, isEnabled: isEnabled))
    }
  }

  private struct LorvexStepShortcut: ViewModifier {
    let step: LorvexStepDirection
    let isEnabled: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
      content.keyboardShortcut(
        isEnabled ? KeyboardShortcut(step.arrowKey(in: layoutDirection), modifiers: .command) : nil)
    }
  }
#endif
