import AppIntents
import LorvexCore

struct UpdateLorvexListIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.update.title", defaultValue: "Update Lorvex List", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.update.description", defaultValue: "Rename or update a Lorvex list from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.name", defaultValue: "Name", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.list.parameter.name.optional_replacement.description", defaultValue: "Optional replacement name.", table: "Localizable", bundle: SystemL10n.bundle))
  var name: String?

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.description", defaultValue: "Description", table: "Localizable", bundle: SystemL10n.bundle),
    description: LocalizedStringResource("system.list.parameter.description.optional_replacement.description", defaultValue: "Optional replacement description.", table: "Localizable", bundle: SystemL10n.bundle))
  var listDescription: String?

  init() {
    list = LorvexListEntity(id: "", name: "", openCount: 0, totalCount: 0)
    name = nil
    listDescription = nil
  }

  init(list: LorvexListEntity, name: String? = nil, description: String? = nil) {
    self.list = list
    self.name = name
    listDescription = description
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let updated = try await LorvexTaskIntentRunner.updateList(
      id: list.id,
      name: name,
      description: listDescription
    )
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.update.dialog", defaultValue: "Updated list \(updated.name) in Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
