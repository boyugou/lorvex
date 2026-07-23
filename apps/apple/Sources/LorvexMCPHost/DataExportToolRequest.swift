import Foundation
import LorvexCore
import MCP

struct DataExportToolRequest {
  let format: LorvexDataExportFormat
  private let entities: Set<String>
  let hasExplicitEntities: Bool

  struct ValidationError: Error { let message: String }

  init(arguments: [String: Value]) throws {
    // Default to JSON only when `format` is OMITTED; a present-but-unrecognized
    // value is rejected rather than silently coerced to JSON.
    if let rawFormat = try StrictScalarArguments.optionalString(
      arguments["format"], field: "format")
    {
      guard let parsed = LorvexDataExportFormat(rawValue: rawFormat) else {
        throw ValidationError(
          message: "Unsupported format '\(rawFormat)'. Use \"json\" or \"csv\".")
      }
      format = parsed
    } else {
      format = .json
    }

    guard let values = try StrictArgumentArray.optionalStrings(
      arguments["entities"], field: "entities")
    else {
      entities = []
      hasExplicitEntities = false
      return
    }
    hasExplicitEntities = !values.isEmpty
    // Validate every element rather than `compactMap`-dropping wrong-typed ones:
    // a dropped element would leave a non-empty request with an EMPTY entity set,
    // which the core reads as "all categories" — so `[123]` would silently trigger
    // a full export. Only the literal "all" sentinel selects a full export.
    let valid = Set(LorvexDataExportCategory.allCases.map(\.rawValue) + ["all"])
    var names = Set<String>()
    for name in values {
      guard valid.contains(name) else {
        let known = (["all"] + LorvexDataExportCategory.allCases.map(\.rawValue).sorted())
          .joined(separator: ", ")
        throw ValidationError(message: "Unknown entity '\(name)'. Valid entities: \(known).")
      }
      names.insert(name)
    }
    entities = names
  }

  func includes(_ entity: String) -> Bool {
    entities.contains("all") || entities.contains(entity)
  }

  /// The selected entity category names for `exportData(entities:format:)`.
  /// The "all" sentinel maps to `[]`, which the full export treats as "every
  /// category". Callers must pass `entities` explicitly before this is used.
  var entityList: [String] {
    entities.contains("all") ? [] : Array(entities)
  }
}
