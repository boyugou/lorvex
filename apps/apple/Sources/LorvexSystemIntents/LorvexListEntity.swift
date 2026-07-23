import AppIntents
import LorvexCore

struct LorvexListEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.list.type", defaultValue: "Lorvex List", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexListEntityQuery()

  var id: LorvexList.ID
  var name: String
  var openCount: Int
  var totalCount: Int

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      subtitle: LocalizedStringResource(
        "system.entity.list.task_summary",
        defaultValue: "\(openCount) open, \(totalCount) total",
        table: "Localizable",
        bundle: SystemL10n.bundle),
      image: .init(systemName: "folder")
    )
  }

  init(id: LorvexList.ID, name: String, openCount: Int, totalCount: Int) {
    self.id = id
    self.name = name
    self.openCount = openCount
    self.totalCount = totalCount
  }

  init(list: LorvexList) {
    self.init(
      id: list.id,
      name: list.name,
      openCount: list.openCount,
      totalCount: list.totalCount
    )
  }
}
