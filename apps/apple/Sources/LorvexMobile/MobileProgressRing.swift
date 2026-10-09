import LorvexCore
import SwiftUI

/// A small determinate circular progress ring: a neutral track, an arc in
/// `tint` for the completed fraction, and at the center a check once complete
/// or, until then, an optional SF Symbol in `tint`. A ring that is skipped (a
/// habit set aside for the day) draws its track as dots and carries the skip
/// glyph in the secondary style, so the day reads as excused by shape and not
/// by color alone.
///
/// The track is the neutral tertiary style, not a faint wash of `tint`. The ring
/// is a habit's check-in control, and while nothing is logged its track is the
/// whole control; a hue at low alpha all but vanishes over a light card for
/// every hue, and over a dark card for deep ones such as indigo and blue, so the
/// unchecked state must not depend on the habit's color.
///
/// A plain trimmed `Circle` rather than `Gauge(.accessoryCircularCapacity)`:
/// that accessory style is built for watch complications and Lock Screen
/// widgets, and inside a regular iOS view it recurses into a stack overflow.
struct MobileProgressRing: View {
  /// Progress in 0...1.
  let value: Double
  var tint: Color = LorvexDesign.Palette.accent
  var size: CGFloat = 32
  var lineWidth: CGFloat = 4
  var isComplete: Bool = false
  /// SF Symbol drawn at the center until the ring is complete, for a ring that
  /// is the only mark identifying what it tracks. Nil leaves the center empty.
  var symbol: String? = nil
  /// Draws the ring as set aside for the day. Ignored once the ring is complete.
  var isSkipped: Bool = false

  private var isShownSkipped: Bool { isSkipped && !isComplete }

  var body: some View {
    ZStack {
      if isShownSkipped {
        LorvexDottedRing(dotDiameter: lineWidth)
          .fill(.tertiary)
      } else {
        Circle()
          .stroke(.tertiary, lineWidth: lineWidth)
        LorvexProgressArc(fraction: value, style: tint, lineWidth: lineWidth)
      }
      if let center = isComplete ? "checkmark" : (isShownSkipped ? LorvexHabitSkip.glyph : symbol) {
        Image(systemName: center)
          .font(.system(size: size * (isComplete ? 0.42 : 0.4), weight: isComplete ? .bold : .semibold))  // lorvex-design-token: allow
          .foregroundStyle(isShownSkipped ? Color.secondary : tint)
          .contentTransition(.symbolEffect(.replace))
      }
    }
    .frame(width: size, height: size)
    .reduceMotionAnimation(.easeInOut(duration: 0.2), value: value)
  }
}
