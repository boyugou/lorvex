#if canImport(AppIntents)
import AppIntents
import LorvexWidgetKitSupport
import LorvexWidgetViews

public struct LorvexWidgetListEntity: AppEntity, Equatable, Identifiable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("widget.entity.list.type", defaultValue: "List", table: "Localizable", bundle: WidgetL10n.bundle))
  public static let defaultQuery = LorvexWidgetListEntityQuery()

  public var id: String
  public var name: String
  public var icon: String?

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name.isEmpty ? id : name)",
      image: icon.map { DisplayRepresentation.Image(systemName: $0) }
    )
  }

  public init(id: String, name: String = "", icon: String? = nil) {
    self.id = id
    self.name = name
    self.icon = icon
  }
}

public struct LorvexWidgetListEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [LorvexWidgetListEntity.ID]) async throws
    -> [LorvexWidgetListEntity]
  {
    let catalog = Self.snapshotLists()
    return identifiers.map { id in
      catalog.first { $0.id == id } ?? LorvexWidgetListEntity(id: id)
    }
  }

  public func suggestedEntities() async throws -> [LorvexWidgetListEntity] {
    Self.snapshotLists()
  }

  public func entities(matching string: String) async throws -> [LorvexWidgetListEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return Self.snapshotLists() }
    return Self.snapshotLists().filter { entity in
      entity.name.localizedCaseInsensitiveContains(query)
        || entity.id.localizedCaseInsensitiveContains(query)
    }
  }

  private static func snapshotLists() -> [LorvexWidgetListEntity] {
    guard let url = LorvexWidgetConfiguration().resolvedSnapshotURL(),
      case .snapshot(let snapshot) = WidgetSnapshotLoader().loadSnapshot(at: url)
    else {
      return []
    }
    return snapshot.lists.map {
      LorvexWidgetListEntity(id: $0.id, name: $0.name, icon: $0.icon)
    }
  }
}
#endif
