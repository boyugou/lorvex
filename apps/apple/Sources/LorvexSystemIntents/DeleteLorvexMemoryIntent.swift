import AppIntents
import LorvexCore

struct DeleteLorvexMemoryIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.memory.delete.title", defaultValue: "Delete Lorvex Memory", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.memory.delete.description", defaultValue: "Delete an AI-writable Lorvex memory entry by key from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.memory.parameter.memory", defaultValue: "Memory", table: "Localizable", bundle: SystemL10n.bundle))
  var memory: LorvexAIMemoryEntity

  init() {
    memory = LorvexAIMemoryEntity(id: "", key: "")
  }

  init(key: String) {
    memory = LorvexAIMemoryEntity(id: key, key: key)
  }

  init(memory: LorvexAIMemoryEntity) {
    self.memory = memory
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    let deletedKey = try await LorvexTaskIntentRunner.deleteMemory(key: memory.key)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.memory.delete.dialog", defaultValue: "Deleted memory: \(deletedKey)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
