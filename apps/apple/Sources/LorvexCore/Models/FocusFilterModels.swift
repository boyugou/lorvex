import Foundation

/// Persisted focus-filter settings that control which tasks surface in widgets and
/// notification extensions while a system Focus mode is active.
///
/// `isActive` is true when `activeProfileID` is non-nil. When `isActive` is true and
/// `showNonFocusTasks` is false, only tasks whose IDs appear in the current focus plan
/// should be projected.
public struct FocusFilterConfiguration: Codable, Equatable, Sendable {
  /// ID of the active focus profile, or `nil` when no system Focus mode is active.
  public var activeProfileID: String?

  /// Whether non-focus tasks should appear in widget and shortcuts surfaces.
  public var showNonFocusTasks: Bool

  /// True when a system Focus mode is active (i.e. `activeProfileID` is set).
  public var isActive: Bool { activeProfileID != nil }

  public init(activeProfileID: String? = nil, showNonFocusTasks: Bool = false) {
    self.activeProfileID = activeProfileID
    self.showNonFocusTasks = showNonFocusTasks
  }

  /// The default inert configuration used when no Focus mode is active.
  public static let inactive = FocusFilterConfiguration()
}

/// One atomically persisted Focus-filter value and its monotonic local revision.
///
/// The revision is not a user-data or sync version. It orders projections made
/// by the app and App Intents extension from the shared App-Group configuration:
/// once revision N has reached the widget/watch sidecar, a delayed projection
/// that read N-1 cannot restore the previous Focus visibility policy.
public struct FocusFilterState: Equatable, Sendable {
  public let configuration: FocusFilterConfiguration
  public let revision: Int
  /// Durable managed-storage generation this policy belongs to. Revisions are
  /// only comparable inside one generation; a factory reset advances the
  /// generation and invalidates every pre-reset writer.
  public let storageGeneration: Int

  public init(
    configuration: FocusFilterConfiguration,
    revision: Int,
    storageGeneration: Int = 0
  ) {
    self.configuration = configuration
    self.revision = max(0, revision)
    self.storageGeneration = max(0, storageGeneration)
  }

  public static let inactive = FocusFilterState(
    configuration: .inactive, revision: 0, storageGeneration: 0)

  public static func inactive(storageGeneration: Int) -> FocusFilterState {
    FocusFilterState(
      configuration: .inactive,
      revision: 0,
      storageGeneration: storageGeneration)
  }
}
