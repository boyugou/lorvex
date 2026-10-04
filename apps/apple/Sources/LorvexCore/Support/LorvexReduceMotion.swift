import SwiftUI

#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Whether the user turned on Reduce Motion in the system's Accessibility
/// settings. SwiftUI does not gate `withAnimation` or `.animation(_:value:)` on
/// this setting, so every Lorvex animation goes through the helpers in this
/// file: with Reduce Motion on, an animated state change applies instantly
/// instead of sliding, scaling, or fading. `script/verify_source_hygiene.py`
/// rejects a raw `withAnimation(` or `.animation(` anywhere else in the sources.
@MainActor
public var lorvexReduceMotionEnabled: Bool {
  #if os(watchOS)
  WKAccessibilityIsReduceMotionEnabled()
  #elseif canImport(UIKit)
  UIAccessibility.isReduceMotionEnabled
  #elseif canImport(AppKit)
  NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  #else
  false
  #endif
}

/// `animation`, or `nil` (no animation) when Reduce Motion is on. For the APIs
/// that take an optional animation, such as `Binding.animation(_:)`.
@MainActor
public func lorvexAnimation(_ animation: Animation = .default) -> Animation? {
  lorvexReduceMotionEnabled ? nil : animation
}

/// `withAnimation`, but with no animation when Reduce Motion is on. Same
/// signature, so a call site only changes the name.
@MainActor
public func lorvexAnimated<Result>(
  _ animation: Animation = .default,
  _ body: () throws -> Result
) rethrows -> Result {
  try withAnimation(lorvexAnimation(animation), body)
}

extension View {
  /// `.animation(_:value:)` that applies no animation when Reduce Motion is on.
  /// Reads the environment, so a view already on screen follows the setting the
  /// moment it changes.
  public func reduceMotionAnimation(_ animation: Animation, value: some Equatable) -> some View {
    modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
  }

  /// `.symbolEffect(.bounce, value:)` that never bounces when Reduce Motion is on.
  public func reduceMotionBounce(value: some Equatable) -> some View {
    modifier(ReduceMotionBounceModifier(value: value))
  }

  /// Scales the view up to `scale` while `isActive`, as a momentary
  /// acknowledgment of a tap, and does nothing when Reduce Motion is on. The
  /// pop has to be skipped rather than left unanimated: without its spring the
  /// scale would jump out and back as a flicker.
  public func reduceMotionPop(isActive: Bool, scale: CGFloat = 1.18) -> some View {
    modifier(ReduceMotionPopModifier(isActive: isActive, scale: scale))
  }
}

extension Binding {
  /// `Binding.animation(_:)` that applies no animation when Reduce Motion is on.
  @MainActor
  public func reduceMotionAnimation(_ animation: Animation = .default) -> Binding<Value> {
    self.animation(lorvexAnimation(animation))
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

private struct ReduceMotionBounceModifier<V: Equatable>: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let value: V

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content.symbolEffect(.bounce, value: value)
    }
  }
}

private struct ReduceMotionPopModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isActive: Bool
  let scale: CGFloat

  func body(content: Content) -> some View {
    content.scaleEffect(isActive && !reduceMotion ? scale : 1)
  }
}
