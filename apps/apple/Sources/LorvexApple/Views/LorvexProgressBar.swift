import LorvexCore
import SwiftUI

/// The app's one determinate progress track: a soft capsule rail filled to a
/// fraction with the tint's gradient. Replaces the stock linear `ProgressView`
/// so checklist, habit, and list progress read as one family and pick up the
/// palette. Callers own the surrounding accessibility framing (label / hidden /
/// ignore) when they compose the bar into a larger element; on its own the bar
/// reports its percentage.
struct LorvexProgressBar: View {
  /// Completion fraction, clamped to `0...1`.
  let value: Double
  var tint: Color = .accentColor
  var height: CGFloat = 6

  private var fraction: Double { min(max(value, 0), 1) }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(tint.opacity(0.16))
        Capsule()
          .fill(tint.gradient)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: height)
    .reduceMotionAnimation(.snappy(duration: 0.28), value: fraction)
    .accessibilityElement()
    .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
  }
}
