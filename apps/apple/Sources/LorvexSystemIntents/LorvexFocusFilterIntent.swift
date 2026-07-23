import AppIntents
import Foundation
import LorvexCore
import LorvexWidgetKitSupport
#if LORVEX_FOCUS_FILTER_EXTENSION
  import LorvexSystemIntents
#endif

// MARK: - Focus Profile Entity

/// Identifies a named Lorvex focus profile that can be associated with a system Focus mode.
///
/// Only the built-in "Lorvex Focus" profile exists; the query suggests it as
/// the sole entity.
public struct LorvexFocusProfileEntity: AppEntity {
  static let builtInID = "Lorvex Focus"
  static let builtInDisplayName = LocalizedStringResource(
    "system.focus_filter.default_profile",
    defaultValue: "Lorvex Focus",
    table: "Localizable",
    bundle: SystemL10n.bundle)

  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.focus_profile.type", defaultValue: "Lorvex Focus Profile", table: "Localizable", bundle: SystemL10n.bundle))
  public static let defaultQuery = LorvexFocusProfileQuery()

  public let id: String

  public var displayRepresentation: DisplayRepresentation {
    if id == Self.builtInID {
      return DisplayRepresentation(title: Self.builtInDisplayName)
    }
    return DisplayRepresentation(title: "\(id)")
  }

  public init(id: String) {
    self.id = id
  }

  /// The built-in profile that activates Lorvex-managed focus mode.
  public static let lorvexFocus = LorvexFocusProfileEntity(id: builtInID)
}

// MARK: - Focus Profile Query

public struct LorvexFocusProfileQuery: EntityQuery {
  public init() {}

  public func entities(for identifiers: [String]) async throws -> [LorvexFocusProfileEntity] {
    identifiers.map { LorvexFocusProfileEntity(id: $0) }
  }

  public func suggestedEntities() async throws -> [LorvexFocusProfileEntity] {
    [.lorvexFocus]
  }
}

// MARK: - Focus Filter Intent

/// Lets users associate a system Focus mode with a Lorvex focus profile.
///
/// When the system activates the linked Focus mode and `showNonFocusTasks` is
/// off, Lorvex hides tasks that are not in the current focus plan from the
/// widget and Apple Watch snapshots. The intent persists its parameters to the
/// shared `FocusFilterStore`; `WidgetSnapshotProjector.focusFilteredTasks`
/// reads that persisted `FocusFilterConfiguration` when projecting the
/// snapshot. This is the filter's only effect — no notification, badge, or
/// Shortcuts path consults it.
public struct LorvexFocusFilterIntent: SetFocusFilterIntent {
  public static let title: LocalizedStringResource = LocalizedStringResource("system.focus_filter.title", defaultValue: "Lorvex Focus", table: "Localizable", bundle: SystemL10n.bundle)
  public static let description: IntentDescription = IntentDescription(LocalizedStringResource("system.focus_filter.description", defaultValue: "Scope a system Focus mode to a Lorvex focus profile, hiding non-focus tasks from widgets.", table: "Localizable", bundle: SystemL10n.bundle))

  // Configured from the system Settings > Focus UI and re-run unattended by the
  // system whenever the linked Focus mode toggles (possibly while locked). It
  // reads no user content and only persists which focus profile is active, so it
  // must not be gated behind authentication or it would fail to apply on lock.
  public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  public var displayRepresentation: DisplayRepresentation {
    let builtInProfileID = LorvexFocusProfileEntity.lorvexFocus.id
    if focusProfile == nil || focusProfile?.id == builtInProfileID {
      return DisplayRepresentation(
        title: LocalizedStringResource("system.focus_filter.title", defaultValue: "Lorvex Focus", table: "Localizable", bundle: SystemL10n.bundle),
        subtitle: LorvexFocusProfileEntity.builtInDisplayName
      )
    }
    return DisplayRepresentation(
      title: LocalizedStringResource("system.focus_filter.title", defaultValue: "Lorvex Focus", table: "Localizable", bundle: SystemL10n.bundle),
      subtitle: "\(focusProfile?.id ?? builtInProfileID)"
    )
  }

  /// The Lorvex focus profile to activate when this system Focus mode is on.
  @Parameter(
    title: LocalizedStringResource("system.focus_filter.parameter.profile", defaultValue: "Focus Profile", table: "Localizable", bundle: SystemL10n.bundle))
  public var focusProfile: LorvexFocusProfileEntity?

  /// When false, the widget and Apple Watch snapshots hide tasks that are not in the current focus list.
  @Parameter(
    title: LocalizedStringResource("system.focus_filter.parameter.show_non_focus_tasks", defaultValue: "Show Non-Focus Tasks", table: "Localizable", bundle: SystemL10n.bundle),
    default: false)
  public var showNonFocusTasks: Bool

  public init() {}

  func apply(
    store: FocusFilterStore,
    republish: @escaping @Sendable () async throws -> Void
  ) async throws {
    let configuration = focusProfile.map {
      FocusFilterConfiguration(
        activeProfileID: $0.id,
        showNonFocusTasks: showNonFocusTasks)
    } ?? .inactive
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
