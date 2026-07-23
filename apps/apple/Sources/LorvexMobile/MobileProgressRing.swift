import LorvexCore
import SwiftUI

/// A small determinate circular progress ring.
///
/// The iOS-safe replacement for `Gauge(.accessoryCircularCapacity)` — that
/// accessory gauge style is built for watchOS/complications and Lock-Screen
/// widgets, and rendering it in a regular iOS view recurses into a stack overflow
/// (it crashed the Habits screen). A plain trimmed `Circle` is stable everywhere
/// and gives us full control of tint, width, and the completed check.
struct MobileProgressRing: View {
  /// Progress in 0...1.
  let value: Double
  var tint: Color = LorvexDesign.Palette.accent
  var size: CGFloat = 32
  var lineWidth: CGFloat = 4
  var isComplete: Bool = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(tint.opacity(0.18), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: min(1, max(0, value)))
        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      if isComplete {
        Image(systemName: "checkmark")
          .font(.system(size: size * 0.42, weight: .bold))
          .foregroundStyle(tint)
      }
    }
    .frame(width: size, height: size)
    .animation(.easeInOut(duration: 0.2), value: value)
  }
}
