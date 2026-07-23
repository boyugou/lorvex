import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct MobileDataExportTransferable: Transferable {
  let content: Data
  let format: MobileDataExportFormat

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .data) { item in
      item.content
    }
    .suggestedFileName { item in
      "lorvex-export.\(item.format.fileExtension)"
    }
  }
}

public enum MobileDataExportFormat: String, CaseIterable, Identifiable, Sendable {
  case json
  case csv
  case zip

  public var id: String { rawValue }

  var title: String {
    switch self {
    case .json: "JSON"
    case .csv: "CSV"
    case .zip: "ZIP"
    }
  }

  var systemImage: String {
    switch self {
    case .json: "curlybraces"
    case .csv: "tablecells"
    case .zip: "doc.zipper"
    }
  }

  var fileExtension: String { rawValue }
}
