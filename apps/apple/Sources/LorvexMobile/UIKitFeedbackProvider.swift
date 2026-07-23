// UIFeedbackGenerator is iOS/iPadOS only; visionOS imports UIKit but does NOT
// vend haptic generators (Vision Pro has no Taptic Engine). Gate the entire
// provider on `!os(visionOS)` so the vision build skips it; visionOS surfaces
// fall back to the no-op feedback provider in LorvexCore.
#if canImport(UIKit) && !os(visionOS)
import UIKit
import LorvexCore

/// iOS/iPadOS haptic feedback implementation backed by `UIFeedbackGenerator`.
///
/// Generators are constructed per-call to avoid retaining non-Sendable state,
/// which is the pattern Apple recommends for short-lived feedback events.
public struct UIKitFeedbackProvider: LorvexFeedbackProviding {
  public init() {}

  @MainActor public func playFeedback(_ kind: LorvexFeedbackKind) {
    switch kind {
    case .taskCompleted:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.impactOccurred()
    case .taskCancelled:
      let gen = UIImpactFeedbackGenerator(style: .soft)
      gen.impactOccurred()
    case .taskReopened:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.impactOccurred()
    case .taskDeferred:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.impactOccurred()
    case .habitCompleted:
      let gen = UINotificationFeedbackGenerator()
      gen.notificationOccurred(.success)
    case .habitMilestoneReached:
      let gen = UINotificationFeedbackGenerator()
      gen.notificationOccurred(.success)
    case .habitReset:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.impactOccurred()
    case .captureSubmitted:
      let gen = UIImpactFeedbackGenerator(style: .light)
      gen.impactOccurred()
    case .contentSaved:
      let gen = UIImpactFeedbackGenerator(style: .soft)
      gen.impactOccurred()
    }
  }
}
#endif
