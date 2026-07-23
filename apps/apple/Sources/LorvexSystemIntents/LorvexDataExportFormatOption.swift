import AppIntents

enum LorvexDataExportFormatOption: String, AppEnum {
  case json
  case csv

  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("system.option.data_export_format.type", defaultValue: "Data Export Format", table: "Localizable", bundle: SystemL10n.bundle))
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .json: .init(title: LocalizedStringResource("system.option.data_export_format.json", defaultValue: "JSON", table: "Localizable", bundle: SystemL10n.bundle)),
    .csv: .init(title: LocalizedStringResource("system.option.data_export_format.csv", defaultValue: "CSV", table: "Localizable", bundle: SystemL10n.bundle)),
  ]
}
