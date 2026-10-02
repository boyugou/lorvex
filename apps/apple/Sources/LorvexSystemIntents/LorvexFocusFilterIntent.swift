import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetKitSupport
#if LORVEX_FOCUS_FILTER_EXTENSION
  import LorvexSystemIntents
#endif

// MARK: - List Entity

/// A Lorvex list a Focus filter can keep visible.
///
/// Declared beside the filter intent, not shared with the Shortcuts list
/// entity, because this file also compiles into the iOS Focus filter extension,
/// which cannot see the Shortcuts module's internal types.
public struct LorvexFocusFilterListEntity: AppEntity, Identifiable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource(
      "system.focus_filter.entity.list", defaultValue: "List", table: "Localizable",
      bundle: SystemL10n.bundle))
  public static let defaultQuery = LorvexFocusFilterListQuery()

  public let id: String
  public let name: String

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name.isEmpty ? id : name)")
  }

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// The unarchived lists, by the names the app shows.
public struct LorvexFocusFilterListQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [String]) async throws -> [LorvexFocusFilterListEntity] {
    let lists = try await Self.lists()
    // A list deleted since the filter was set keeps its id, so the filter
    // still reads back; it simply matches no task.
    return identifiers.map { id in
      lists.first { $0.id == id } ?? LorvexFocusFilterListEntity(id: id, name: "")
    }
  }

  public func suggestedEntities() async throws -> [LorvexFocusFilterListEntity] {
    try await Self.lists()
  }

  public func entities(matching string: String) async throws -> [LorvexFocusFilterListEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let lists = try await Self.lists()
    guard !query.isEmpty else { return lists }
    return lists.filter { $0.name.localizedStandardContains(query) }
  }

  private static func lists() async throws -> [LorvexFocusFilterListEntity] {
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    return try await core.loadLists().lists
      .filter { !$0.isArchived }
      .map { LorvexFocusFilterListEntity(id: $0.id, name: $0.displayName) }
  }
}

// MARK: - Focus Filter Intent

/// Narrows Lorvex's glances to chosen lists while a system Focus mode is on.
///
/// When the system turns on the Focus mode this filter belongs to, the widgets
/// and the Apple Watch show only Today's tasks in `lists` and leave out the
/// day's briefing. The intent persists the choice to the shared
/// `FocusFilterStore`; `WidgetSnapshotProjector` reads that
/// `FocusFilterConfiguration` when it projects the snapshot. This is the
/// filter's only effect: the app itself, notifications, and Shortcuts keep
/// every list. Choosing no list narrows nothing.
public struct LorvexFocusFilterIntent: SetFocusFilterIntent {
  public static let title: LocalizedStringResource = LocalizedStringResource(
    "system.focus_filter.title", defaultValue: "Lorvex", table: "Localizable",
    bundle: SystemL10n.bundle)
  public static let description: IntentDescription = IntentDescription(
    LocalizedStringResource(
      "system.focus_filter.description",
      defaultValue:
        "While this Focus is on, Lorvex’s widgets and Apple Watch show only the tasks in the lists you choose.",
      table: "Localizable", bundle: SystemL10n.bundle))

  // Configured from the system Settings > Focus UI and re-run unattended by the
  // system whenever the linked Focus mode toggles (possibly while locked). It
  // reads no task content and only persists list ids, so it must not be gated
  // behind authentication or it would fail to apply on lock.
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  public var displayRepresentation: DisplayRepresentation {
    let names = (lists ?? []).map(\.name).filter { !$0.isEmpty }
    guard !names.isEmpty else {
      return DisplayRepresentation(
        title: Self.title,
        subtitle: LocalizedStringResource(
          "system.focus_filter.all_lists", defaultValue: "All lists", table: "Localizable",
          bundle: SystemL10n.bundle))
    }
    return DisplayRepresentation(
      title: Self.title,
      subtitle: "\(names.formatted(.list(type: .and)))")
  }

  /// The lists whose tasks stay on the widgets and the watch while this Focus
  /// mode is on. Empty or unset narrows nothing.
  @Parameter(
    title: LocalizedStringResource(
      "system.focus_filter.parameter.lists", defaultValue: "Lists", table: "Localizable",
      bundle: SystemL10n.bundle))
  public var lists: [LorvexFocusFilterListEntity]?

  public init() {}

  func apply(
    store: FocusFilterStore,
    republish: @escaping @Sendable () async throws -> Void
  ) async throws {
    let configuration = FocusFilterConfiguration(listIDs: (lists ?? []).map(\.id))
    // Persist first: the projector reads this App-Group value while rebuilding
    // the sidecar. If the rebuild fails, propagate the error so the system can
    // retry instead of reporting a Focus transition that never reached widgets.
    _ = try await store.save(configuration)
    try await republish()
  }

  public func perform() async throws -> some IntentResult {
    let appGroupID = LorvexProductMetadata.appGroupIdentifier
    let store = FocusFilterStore(
      managedDatabasePath: try SwiftLorvexCoreService.managedDatabasePath())
    let core = LorvexCoreRuntimeFactory.makeForAppIntent()
    let configuration = LorvexWidgetConfiguration(appGroupID: appGroupID)
    try await apply(store: store) {
      _ = try await WidgetSnapshotLiveRefresher.live(configuration: configuration)
        .refresh(core: core)
    }
    return .result()
  }
}
