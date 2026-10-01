import SwiftUI

/// The haptic kinds views in this module play through `lorvexSensoryFeedback`.
///
/// A small closed set rather than SwiftUI's own `SensoryFeedback`, so the
/// module's haptics stay a deliberate vocabulary and call sites need no
/// platform checks: SwiftPM also compiles `LorvexMobile` for macOS, where the
/// modifier below is a no-op.
public enum LorvexSensoryFeedback: Equatable, Sendable {
  case success
  case selection
  case impact(weight: Weight)

  public enum Weight: Equatable, Sendable {
    case medium
  }
}

extension View {
  /// Plays `feedback` whenever `trigger` changes.
  ///
  /// Backed by SwiftUI's `.sensoryFeedback` on iOS/iPadOS; a no-op in the
  /// macOS SwiftPM build of this module, so call sites need no `#if os(iOS)`.
  public func lorvexSensoryFeedback<T: Equatable>(
    _ feedback: LorvexSensoryFeedback,
    trigger: T
  ) -> some View {
    #if os(iOS)
      self.sensoryFeedback(feedback.swiftUIFeedback, trigger: trigger)
    #else
      self
    #endif
  }

  /// `condition`-gated variant of `lorvexSensoryFeedback(_:trigger:)`: fires
  /// only when `condition(oldValue, newValue)` is true, mirroring SwiftUI's
  /// `sensoryFeedback(_:trigger:condition:)`. Platform behavior is identical to
  /// the unconditional overload above.
  public func lorvexSensoryFeedback<T: Equatable>(
    _ feedback: LorvexSensoryFeedback,
    trigger: T,
    condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool
  ) -> some View {
    #if os(iOS)
      self.sensoryFeedback(feedback.swiftUIFeedback, trigger: trigger, condition: condition)
    #else
      self
    #endif
  }
}

#if os(iOS)
extension LorvexSensoryFeedback {
  fileprivate var swiftUIFeedback: SensoryFeedback {
    switch self {
    case .success:
      return .success
    case .selection:
      return .selection
    case .impact(weight: .medium):
      return .impact(weight: .medium)
    }
  }
}
#endif
