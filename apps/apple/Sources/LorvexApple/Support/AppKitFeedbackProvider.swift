import AppKit
import LorvexCore

/// macOS haptic feedback implementation backed by `NSHapticFeedbackManager`.
///
/// Constructs no stored state; each call creates a fresh interaction with the
/// system performer, which is the idiomatic AppKit pattern.
struct AppKitFeedbackProvider: LorvexFeedbackProviding {
  @MainActor func playFeedback(_ kind: LorvexFeedbackKind) {
    let performer = NSHapticFeedbackManager.defaultPerformer
    switch kind {
    case .taskCompleted:
      performer.perform(.alignment, performanceTime: .default)
    case .taskCancelled:
      performer.perform(.alignment, performanceTime: .default)
    case .taskReopened:
      performer.perform(.alignment, performanceTime: .default)
    case .taskDeferred:
      performer.perform(.alignment, performanceTime: .default)
    case .habitCompleted:
      performer.perform(.levelChange, performanceTime: .default)
    case .habitMilestoneReached:
      // macOS vends only three system patterns; `.levelChange` is the most
      // pronounced, so a milestone reuses it as the strongest available note.
      performer.perform(.levelChange, performanceTime: .now)
    case .habitReset:
      performer.perform(.alignment, performanceTime: .default)
    case .captureSubmitted:
      performer.perform(.alignment, performanceTime: .default)
    case .contentSaved:
      performer.perform(.alignment, performanceTime: .default)
    }
  }
}
