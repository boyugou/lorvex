import AppIntents
import LorvexCore

struct LorvexTaskEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.task.type", defaultValue: "Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexTaskEntityQuery()

  var id: LorvexTask.ID
  var title: String
  var status: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title)",
      subtitle: LorvexTaskStatusOption.localizedLabel(forRawStatus: status),
      image: .init(systemName: status == "completed" ? "checkmark.circle" : "circle")
    )
  }

  init(id: LorvexTask.ID, title: String, status: String) {
    self.id = id
    self.title = title
    self.status = status
  }

  init(task: LorvexTask) {
    self.init(id: task.id, title: task.title, status: task.status.rawValue)
  }
}
