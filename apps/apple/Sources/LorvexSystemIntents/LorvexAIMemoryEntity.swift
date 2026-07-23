import AppIntents
import LorvexCore

struct LorvexAIMemoryEntity: AppEntity, Identifiable {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.entity.ai_memory.type", defaultValue: "AI-Writable Lorvex Memory", table: "Localizable", bundle: SystemL10n.bundle))
  static let defaultQuery = LorvexAIMemoryEntityQuery()

  var id: String
  var key: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(key)",
      subtitle: LocalizedStringResource("system.entity.ai_memory.subtitle", defaultValue: "AI-writable", table: "Localizable", bundle: SystemL10n.bundle),
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
