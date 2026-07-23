import AppIntents
import LorvexCore

struct CreateLorvexListIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.create.title", defaultValue: "Create Lorvex List", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.create.description", defaultValue: "Create a Lorvex list from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.name", defaultValue: "Name", table: "Localizable", bundle: SystemL10n.bundle))
  var name: String

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.description", defaultValue: "Description", table: "Localizable", bundle: SystemL10n.bundle))
  var listDescription: String?

  init() {
    name = ""
    listDescription = nil
  }

  init(name: String, description: String? = nil) {
    self.name = name
    listDescription = description
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let list = try await LorvexTaskIntentRunner.createList(
      name: name,
      description: listDescription
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.create.dialog", defaultValue: "Created list \(list.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
