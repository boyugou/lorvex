import Foundation

extension AppSettingsStore {
  static func loadedCalendarIDs(_ values: [String]?) -> Set<String> {
    Set((values ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty })
  }

  static func persistedCalendarIDs(_ values: Set<String>) -> [String] {
    values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted()
  }
}
