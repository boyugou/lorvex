import Foundation

public enum LorvexSystemIntentRunner {}

/// Cross-launch handoff for a single pending request (a destination, a task id,
/// or a quick action such as presenting capture) written by an App Intent /
/// widget control and drained by the app on scene-active.
///
/// Suite resolution, in order: an explicitly injected `defaults`; the
/// `withScopedSuiteName` task-local (test isolation); otherwise the shared
/// App-Group suite so an out-of-process control reaches the app, falling back to
/// `.standard` only when that suite is unavailable. Storing one kind of request
/// clears any pending request of another kind — at most one is ever pending.
public struct LorvexIntentHandoffStore {
  @TaskLocal private static var scopedSuiteName: String?

  private let defaults: UserDefaults

  public static func withScopedSuiteName<T>(
    _ suiteName: String,
    operation: () throws -> T
  ) rethrows -> T {
    try $scopedSuiteName.withValue(suiteName, operation: operation)
  }

  public nonisolated(nonsending) static func withScopedSuiteName<T>(
    _ suiteName: String,
    operation: nonisolated(nonsending) () async throws -> T
  ) async rethrows -> T {
    try await $scopedSuiteName.withValue(suiteName, operation: operation)
  }

  @MainActor
  public static func withMainActorScopedSuiteName<T>(
    _ suiteName: String,
    operation: @MainActor () async throws -> T
  ) async rethrows -> T {
    try await $scopedSuiteName.withValue(suiteName, operation: operation)
  }

  public init(defaults: UserDefaults? = nil) {
    if let defaults {
      self.defaults = defaults
    } else if let scopedSuiteName = Self.scopedSuiteName,
      let scopedDefaults = UserDefaults(suiteName: scopedSuiteName)
    {
      self.defaults = scopedDefaults
    } else if let sharedDefaults = UserDefaults(
      suiteName: LorvexProductMetadata.appGroupIdentifier)
    {
      // Default to the App-Group suite so an out-of-process writer (the Control
      // Center Today control runs in the widget-extension process) lands its
      // handoff where the app reads it. `.standard` there would be the
      // extension's private domain, invisible to the app.
      self.defaults = sharedDefaults
    } else {
      self.defaults = .standard
    }
  }

  public func storeDestination(_ rawDestination: String) {
    clear()
    defaults.set(rawDestination, forKey: LorvexIntentHandoffKeys.destination)
  }

  public func storeTask(_ taskID: LorvexTask.ID) {
    clear()
    defaults.set(taskID, forKey: LorvexIntentHandoffKeys.taskID)
  }

  public func storeQuickAction(_ action: LorvexQuickAction) {
    clear()
    defaults.set(action.rawValue, forKey: LorvexIntentHandoffKeys.quickAction)
  }

  public func consumeDestination() -> String? {
    guard let rawValue = defaults.string(forKey: LorvexIntentHandoffKeys.destination),
      !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.destination)
    return rawValue
  }

  public func consumeTaskID() -> LorvexTask.ID? {
    guard let taskID = defaults.string(forKey: LorvexIntentHandoffKeys.taskID),
      !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.taskID)
    return taskID
  }

  /// The quick action a control asked for, consumed once. A stored value that
  /// names no action is dropped.
  public func consumeQuickAction() -> LorvexQuickAction? {
    guard let rawValue = defaults.string(forKey: LorvexIntentHandoffKeys.quickAction) else {
      return nil
    }
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.quickAction)
    return LorvexQuickAction(rawValue: rawValue)
  }

  public func clear() {
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.destination)
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.taskID)
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.quickAction)
  }
}
