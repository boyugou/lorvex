import AppIntents
import LorvexCore

struct SaveLorvexMemoryIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.memory.save.title", defaultValue: "Save Lorvex Memory", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.memory.save.description", defaultValue: "Save an AI-writable Lorvex memory entry from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.memory.parameter.key", defaultValue: "Key", table: "Localizable", bundle: SystemL10n.bundle))
  var key: String

  @Parameter(
    title: LocalizedStringResource("system.memory.parameter.content", defaultValue: "Content", table: "Localizable", bundle: SystemL10n.bundle))
  var content: String

  init() {
    key = ""
    content = ""
  }

  init(key: String, content: String) {
    self.key = key
    self.content = content
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let entry = try await LorvexTaskIntentRunner.saveMemory(key: key, content: content)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.memory.save.dialog", defaultValue: "Saved memory: \(entry.key)",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
