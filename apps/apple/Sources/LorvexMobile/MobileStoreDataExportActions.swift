import Foundation
import LorvexCore

extension MobileStore {
  /// Exports the selected categories in the given format and returns the file
  /// bytes ready to share. JSON/CSV are UTF-8 encodings of the rendered string;
  /// ZIP is a `.zip` package with one JSON file per category plus a manifest.
  ///
  /// Returns nil when an export is already running, no categories are selected,
  /// or the core read fails (with `errorMessage` set in the failure case).
  public func exportData(
    format: MobileDataExportFormat,
    categories: Set<LorvexDataExportCategory>
  ) async -> Data? {
    guard !isExportingData, !categories.isEmpty else { return nil }
    isExportingData = true
    defer { isExportingData = false }

    do {
      let entities = LorvexDataExportCategory.allCases
        .filter { categories.contains($0) }
        .map(\.rawValue)
      let output: Data
      switch format {
      case .zip:
        output = try await core.exportDataZip(
          entities: entities,
          generatedAt: LorvexDateFormatters.iso8601.string(from: Date()),
          appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
      case .json, .csv:
        let string = try await core.exportData(
          entities: entities,
          format: format.rawValue,
          appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          generatedAt: LorvexDateFormatters.iso8601.string(from: Date()))
        output = Data(string.utf8)
      }
      errorMessage = nil
      return output
    } catch {
      await presentUserFacingError(error)
      return nil
    }
  }
}
