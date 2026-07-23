import LorvexCore
import MCP

enum ExportFileMetadata {
  static func data(format: LorvexDataExportFormat) -> [String: Value] {
    [
      "filename": .string("lorvex-export.\(format.rawValue)"),
      "content_type": .string(format.contentType),
      "file_extension": .string(format.rawValue),
      "resource_uri": .string("lorvex://exports/lorvex-export.\(format.rawValue)"),
    ]
  }

  static var calendarICS: [String: Value] {
    [
      "filename": .string("lorvex-calendar.ics"),
      "content_type": .string("text/calendar"),
      "file_extension": .string("ics"),
      "resource_uri": .string("lorvex://exports/lorvex-calendar.ics"),
    ]
  }
}

private extension LorvexDataExportFormat {
  var contentType: String {
    switch self {
    case .json: "application/json"
    case .csv: "text/csv"
    }
  }
}
