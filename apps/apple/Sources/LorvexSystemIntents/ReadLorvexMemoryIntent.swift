import AppIntents
import LorvexCore

struct ReadLorvexMemoryIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.memory.read.title", defaultValue: "Read Lorvex Memory", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.memory.read.description", defaultValue: "Read a Lorvex memory entry by key from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.memory.parameter.memory", defaultValue: "Memory", table: "Localizable", bundle: SystemL10n.bundle))
  var memory: LorvexMemoryEntity

  init() {
    memory = LorvexMemoryEntity(id: "", key: "")
  }

  init(key: String) {
    memory = LorvexMemoryEntity(id: key, key: key)
  }

  init(memory: LorvexMemoryEntity) {
    self.memory = memory
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try await LorvexTaskIntentRunner.readMemory(key: memory.key)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.memory.read.dialog", defaultValue: "\(entry.key): \(entry.content)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
