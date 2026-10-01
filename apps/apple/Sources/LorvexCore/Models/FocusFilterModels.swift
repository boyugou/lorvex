import Foundation

/// The lists a system Focus mode narrows Lorvex's glances to.
///
/// While the Focus mode this configuration belongs to is on, the widgets and the
/// Apple Watch show only Today's tasks in ``listIDs`` and leave out the day's
/// briefing, which speaks about the whole day. An empty set means no Focus mode
/// narrows them. ``FocusFilterStore`` persists it beside the managed database so
/// the app and the App Intents extension read one value.
public struct FocusFilterConfiguration: Codable, Equatable, Sendable {
  /// The lists whose tasks stay visible; empty when no Focus mode narrows the
  /// glances.
  public var listIDs: [String]

  /// True when a Focus mode narrows the glances to ``listIDs``.
  public var isActive: Bool { !listIDs.isEmpty }

  public init(listIDs: [String] = []) {
    self.listIDs = listIDs
  }

  /// The configuration that narrows nothing.
  public static let inactive = FocusFilterConfiguration()

  enum CodingKeys: String, CodingKey {
    case listIDs
  }

  /// A stored configuration that names no lists decodes as ``inactive``, so a
  /// state file of another shape never blocks the store's next revision.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    listIDs = try container.decodeIfPresent([String].self, forKey: .listIDs) ?? []
  }
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
