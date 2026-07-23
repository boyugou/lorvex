import Foundation

public enum LorvexSystemIntentRunner {}

/// Cross-launch handoff for a single pending navigation target (a destination or
/// a task id) written by an App Intent / widget control and drained by the app on
/// scene-active.
///
/// Suite resolution, in order: an explicitly injected `defaults`; the
/// `withScopedSuiteName` task-local (test isolation); otherwise the shared
/// App-Group suite so an out-of-process control reaches the app, falling back to
/// `.standard` only when that suite is unavailable. Storing a destination clears
/// any pending task id and vice versa — at most one target is ever pending.
public struct LorvexIntentHandoffStore {
  @TaskLocal private static var scopedSuiteName: String?

  private let defaults: UserDefaults

  public static func withScopedSuiteName<T>(
    _ suiteName: String,
    operation: () throws -> T
  ) rethrows -> T {
    try $scopedSuiteName.withValue(suiteName, operation: operation)
  }

  public static func withScopedSuiteName<T>(
    _ suiteName: String,
    operation: () async throws -> T
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
      // Center focus control runs in the widget-extension process) lands its
      // handoff where the app reads it. `.standard` there would be the
      // extension's private domain, invisible to the app.
      self.defaults = sharedDefaults
    } else {
      self.defaults = .standard
    }
  }

  public func storeDestination(_ rawDestination: String) {
    defaults.set(rawDestination, forKey: LorvexIntentHandoffKeys.destination)
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.taskID)
  }

  public func storeTask(_ taskID: LorvexTask.ID) {
    defaults.set(taskID, forKey: LorvexIntentHandoffKeys.taskID)
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.destination)
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

  public func clear() {
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.destination)
    defaults.removeObject(forKey: LorvexIntentHandoffKeys.taskID)
  }
}
