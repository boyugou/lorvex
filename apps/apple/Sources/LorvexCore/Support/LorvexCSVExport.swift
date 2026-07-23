import Foundation

extension LorvexDataExporter {
  static func csvSection(header: String, columns: [String], rows: [[String]]) -> String {
    var lines = ["## \(header)", csvRow(columns)]
    lines += rows.map(csvRow)
    return lines.joined(separator: "\n")
  }

  static func csvRow(_ fields: [String]) -> String {
    fields.map(csvEscape).joined(separator: ",")
  }

  /// RFC 4180 escaping: enclose in double-quotes if field contains comma, double-quote, or newline;
  /// escape embedded double-quotes by doubling them.
  public static func csvEscape(_ field: String) -> String {
    let needsQuoting = field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r")
    guard needsQuoting else { return field }
    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}
