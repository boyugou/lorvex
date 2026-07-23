import AppIntents
import LorvexWidgetKitSupport

/// A lightweight AppEntity that identifies a Lorvex task by its opaque string ID.
///
/// Used exclusively in widget-hosted intents where the full `LorvexTaskEntity`
/// (which depends on `AppCoreFactory` and `LorvexApple`) is unavailable.
/// The entity holds only the ID; the intent runner resolves it against the core
/// at perform time.
public struct WidgetTaskEntity: AppEntity, Identifiable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("widget.intent.entity.task", defaultValue: "Task", table: "Localizable", bundle: WidgetSupportL10n.bundle))
  public static let defaultQuery = WidgetTaskEntityQuery()

  public var id: String
  public var title: String

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title.isEmpty ? id : title)")
  }

  public init(id: String, title: String = "") {
    self.id = id
    self.title = title
  }
}
