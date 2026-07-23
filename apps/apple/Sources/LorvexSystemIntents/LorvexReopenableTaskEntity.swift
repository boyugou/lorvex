import AppIntents
import LorvexCore

struct LorvexReopenableTaskEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.reopenable_task.type", defaultValue: "Reopenable Lorvex Task", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexReopenableTaskEntityQuery()

  var id: LorvexTask.ID
  var title: String
  var status: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(title)",
      subtitle: LorvexTaskStatusOption.localizedLabel(forRawStatus: status),
      image: .init(systemName: status == "cancelled" ? "xmark.circle" : "arrow.uturn.backward.circle")
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
