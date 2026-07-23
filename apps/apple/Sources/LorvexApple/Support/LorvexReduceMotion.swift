import AppKit
import SwiftUI

/// Whether the user enabled System Settings › Accessibility › Display › "Reduce
/// motion". SwiftUI does not gate `withAnimation` / `.animation(_:value:)` on
/// this setting, so Lorvex routes its animations through the helpers below to
/// honor it — animated state changes apply instantly instead of sliding/fading.
@MainActor var lorvexReduceMotionEnabled: Bool {
  NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

/// `withAnimation`, but with no animation when Reduce Motion is enabled. Drop-in
/// for `withAnimation(_:_:)` — same signature, so call sites only change the name.
@MainActor
func lorvexAnimated<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
  try withAnimation(lorvexReduceMotionEnabled ? nil : animation, body)
}

extension View {
  /// `.animation(_:value:)` that drops to no animation under Reduce Motion.
  func reduceMotionAnimation(_ animation: Animation, value: some Equatable) -> some View {
    modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
  }
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let animation: Animation
  let value: V

  func body(content: Content) -> some View {
    content.animation(reduceMotion ? nil : animation, value: value)
  }
}
