/// Cross-platform protocol for user-facing haptic feedback.
///
/// Implementations are platform-specific (AppKit on macOS, UIKit on iOS);
/// `NoOpFeedbackProvider` is the default for tests and contexts where
/// platform APIs are unavailable.

// MARK: - Kind

/// Discrete feedback events emitted by store actions.
public enum LorvexFeedbackKind: Sendable {
  /// Fired when a task is marked complete.
  case taskCompleted
  /// Fired when a task is cancelled.
  case taskCancelled
  /// Fired when a task is reopened (returned to open status).
  case taskReopened
  /// Fired when a task is deferred to a later day.
  case taskDeferred
  /// Fired when a habit is marked complete for the day.
  case habitCompleted
  /// Fired when a habit completion crosses a milestone waypoint — a stronger,
  /// celebratory note than an ordinary completion.
  case habitMilestoneReached
  /// Fired when today's habit completion is reset.
  case habitReset
  /// Fired when a Quick Capture entry is submitted.
  case captureSubmitted
  /// Fired when review content is saved.
  case contentSaved
}

// MARK: - Protocol

/// Delivers haptic feedback for significant user actions.
///
/// All implementations must be safe to call from `@MainActor` context because
/// AppKit and UIKit feedback APIs require the main thread.
public protocol LorvexFeedbackProviding: Sendable {
  @MainActor func playFeedback(_ kind: LorvexFeedbackKind)
}

// MARK: - No-op

/// A `LorvexFeedbackProviding` implementation that silently discards every
/// feedback request. Used as the default in tests and server-side contexts.
public struct NoOpFeedbackProvider: LorvexFeedbackProviding {
  public init() {}

  @MainActor public func playFeedback(_ kind: LorvexFeedbackKind) {}
}
