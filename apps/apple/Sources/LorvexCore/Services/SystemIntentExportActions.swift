import Foundation

extension LorvexSystemIntentRunner {
  public static func exportData(
    format: String,
    entities: [String],
    core: any LorvexCoreServicing
  ) async throws -> String {
    let trimmedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedFormat = trimmedFormat.isEmpty ? "json" : trimmedFormat
    guard normalizedFormat == "json" || normalizedFormat == "csv" else {
      throw LorvexCoreError.validation(
        field: "format", message: "Data export format must be json or csv.")
    }
    let normalizedEntities = entities
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return try await core.exportData(entities: normalizedEntities, format: normalizedFormat)
  }

  public static func exportCalendarICS(
    from: String?,
    to: String?,
    core: any LorvexCoreServicing
  ) async throws -> String {
    try await core.exportCalendarICS(from: from.trimmedNilIfEmpty, to: to.trimmedNilIfEmpty)
  }
}
