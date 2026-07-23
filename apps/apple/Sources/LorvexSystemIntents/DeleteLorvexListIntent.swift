import AppIntents
import LorvexCore

struct DeleteLorvexListIntent: LorvexAuthenticatedIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.list.delete.title", defaultValue: "Delete Lorvex List", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.list.delete.description", defaultValue: "Delete an empty Lorvex list from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.list.parameter.list", defaultValue: "List", table: "Localizable", bundle: SystemL10n.bundle))
  var list: LorvexListEntity

  init() {
    list = LorvexListEntity(id: "", name: "", openCount: 0, totalCount: 0)
  }

  init(list: LorvexListEntity) {
    self.list = list
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    try await requestLorvexDestructiveConfirmation(
      IntentDialog(
        LocalizedStringResource(
          "system.confirm.delete", defaultValue: "Delete this item? This can't be undone.",
          table: "Localizable", bundle: SystemL10n.bundle)))
    _ = try await LorvexTaskIntentRunner.deleteList(id: list.id)
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.list.delete.dialog", defaultValue: "Deleted list \(list.name) from Lorvex.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
