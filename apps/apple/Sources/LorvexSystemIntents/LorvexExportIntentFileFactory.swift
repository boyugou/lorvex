import AppIntents
import Foundation
import UniformTypeIdentifiers

enum LorvexExportIntentFileFactory {
  static func dataFile(content: String, format: LorvexDataExportFormatOption) -> IntentFile {
    IntentFile(
      data: Data(content.utf8),
      filename: "lorvex-export.\(format.fileExtension)",
      type: format.contentType
    )
  }

  static func calendarFile(content: String) -> IntentFile {
    IntentFile(
      data: Data(content.utf8),
      filename: "lorvex-calendar.ics",
      type: .lorvexCalendarICS
    )
  }
}

extension LorvexDataExportFormatOption {
  var fileExtension: String { rawValue }

  var contentType: UTType {
    switch self {
    case .json: .json
    case .csv: .commaSeparatedText
    }
  }
}

private extension UTType {
  static let lorvexCalendarICS = UTType("com.apple.ical.ics") ?? .data
}
