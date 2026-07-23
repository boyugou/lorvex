import AppIntents
import LorvexCore

struct LorvexMemoryEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.memory.type", defaultValue: "Lorvex Memory", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexMemoryEntityQuery()

  var id: String
  var key: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(key)",
      image: .init(systemName: "brain.head.profile")
    )
  }

  init(id: String, key: String) {
    self.id = id
    self.key = key
  }

  init(entry: MemoryEntry) {
    self.init(id: entry.key, key: entry.key)
  }
}
