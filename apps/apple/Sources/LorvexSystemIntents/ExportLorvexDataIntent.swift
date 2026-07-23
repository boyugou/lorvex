import AppIntents
import LorvexCore

struct ExportLorvexDataIntent: LorvexLocalAuthIntent {
  static let title: LocalizedStringResource = LocalizedStringResource("system.export.data.title", defaultValue: "Export Lorvex Data", table: "Localizable", bundle: SystemL10n.bundle)
  static let description = IntentDescription(LocalizedStringResource("system.export.data.description", defaultValue: "Prepare a Lorvex JSON or CSV data export from Shortcuts or Siri.", table: "Localizable", bundle: SystemL10n.bundle))

  @Parameter(
    title: LocalizedStringResource("system.export.parameter.format", defaultValue: "Format", table: "Localizable", bundle: SystemL10n.bundle))
  var format: LorvexDataExportFormatOption

  @Parameter(
    title: LocalizedStringResource("system.export.parameter.entities", defaultValue: "Entities", table: "Localizable", bundle: SystemL10n.bundle))
  var entities: [LorvexDataExportEntityOption]

  init() {
    format = .json
    entities = [.all]
  }

  init(format: LorvexDataExportFormatOption, entities: [LorvexDataExportEntityOption] = [.all]) {
    self.format = format
    self.entities = entities
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
    let output = try await LorvexTaskIntentRunner.exportData(
      format: format.rawValue,
      entities: entities.map(\.coreEntityName)
    )
    let file = LorvexExportIntentFileFactory.dataFile(content: output, format: format)
    return .result(
      value: file,
      dialog: IntentDialog(
        LocalizedStringResource(
          "system.export.data.dialog",
          defaultValue: "Prepared \(format.rawValue.uppercased()) export.",
          table: "Localizable", bundle: SystemL10n.bundle)))
  }
}
