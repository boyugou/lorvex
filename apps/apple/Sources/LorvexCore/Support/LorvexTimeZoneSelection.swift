import Observation

/// A settings picker keeps its current choice until the new zone has saved
/// and refreshed. While that is in flight, another tap cannot start a second
/// write; a failed choice stays open for a retry.
@MainActor @Observable
public final class LorvexTimeZoneSelection {
  public private(set) var pendingIdentifier: String?

  public init() {}

  public var isSaving: Bool { pendingIdentifier != nil }

  /// True when the picker can close. Selecting the current zone is a no-op.
  public func select(
    _ identifier: String, current: String,
    save: @MainActor (String) async -> Bool
  ) async -> Bool {
    guard !isSaving else { return false }
    guard identifier != current else { return true }
    pendingIdentifier = identifier
    defer { pendingIdentifier = nil }
    return await save(identifier)
  }
}
