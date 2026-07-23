import SwiftUI

/// The haptic kinds views in this module play through `lorvexSensoryFeedback`.
///
/// Deliberately not SwiftUI's own `SensoryFeedback`: that type (and the
/// `.sensoryFeedback` modifier itself) is `@available(..., visionOS 26.0, *)`,
/// but `Sources/LorvexMobile` is compiled against both the iOS target
/// (`LorvexMobile`, floor iOS 18.0) and the visionOS target (`LorvexMobileVision`,
/// floor visionOS 2.0). Naming SwiftUI's type in a shared, unguarded signature
/// would fail the visionOS build outright — this proxy lets call sites name a
/// haptic without the visionOS compilation ever referencing the unavailable type.
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
  /// Backed by SwiftUI's `.sensoryFeedback` on iOS/iPadOS, where the haptic
  /// engine and the API both exist. A no-op everywhere else — currently just
  /// visionOS, which has no Taptic Engine and (independently) doesn't ship the
  /// API until visionOS 26, past this app's visionOS 2.0 floor. Keeps a single
  /// call site correct on both targets instead of `#if os(iOS)` at every use.
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
