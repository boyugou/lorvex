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

  /// The first scalars that make a spreadsheet read a cell as a formula. A title, note, or
  /// name an assistant or an import supplied could otherwise run one when the export is
  /// opened (a hyperlink that sends cell data to a server, a legacy DDE command).
  private static let formulaStarts: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

  /// RFC 4180 escaping: enclose in double-quotes if field contains comma, double-quote, or newline;
  /// escape embedded double-quotes by doubling them. A field that starts like a spreadsheet
  /// formula (`=`, `+`, `-`, `@`, a tab, or a carriage return) gets a leading apostrophe, so
  /// the spreadsheet shows it as text.
  ///
  /// The field is read as Unicode scalars, the units a CSV reader splits on. Read
  /// as characters it would miss a CR LF pair (one `Character` that is neither
  /// `"\n"` nor `"\r"`) and a comma or quote followed by a combining mark, and
  /// leave the field unquoted.
  public static func csvEscape(_ field: String) -> String {
    let field =
      field.unicodeScalars.first.map(formulaStarts.contains) == true ? "'" + field : field
    let needsQuoting = field.unicodeScalars.contains { scalar in
      scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
    }
    guard needsQuoting else { return field }
    var escaped = "\""
    for scalar in field.unicodeScalars {
      if scalar == "\"" { escaped += "\"" }
      escaped.unicodeScalars.append(scalar)
    }
    return escaped + "\""
  }
}
