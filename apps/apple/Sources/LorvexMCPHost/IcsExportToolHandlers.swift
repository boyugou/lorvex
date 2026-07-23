import Foundation
import MCP
import LorvexCore

extension ToolRegistry {
  func exportCalendarIcsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let from = try StrictScalarArguments.optionalString(arguments["from"], field: "from")
    let to = try StrictScalarArguments.optionalString(arguments["to"], field: "to")

    let ics = try await coreBridge.exportCalendarIcs(from: from, to: to)

    var structured = ExportFileMetadata.calendarICS
    let resourceURI = structured["resource_uri"]?.stringValue ?? "lorvex://exports/lorvex-calendar.ics"
    structured["byte_count"] = .int(ics.utf8.count)
    return CallTool.Result(
      content: [
        .text(text: "Calendar ICS prepared. See the embedded resource.", annotations: nil, _meta: nil),
        // Preserve the exact calendar file while preventing event titles and
        // notes from becoming model-facing prompt text. The blob is base64 on
        // the wire and explicitly intended for the end user only.
        .resource(
          resource: .binary(
            Data(ics.utf8),
            uri: resourceURI,
            mimeType: structured["content_type"]?.stringValue),
          annotations: .init(audience: [.user]),
          _meta: nil),
      ],
      structuredContent: Optional.some(.object(structured)),
      isError: false
    )
  }
}

extension CoreBridgeClient {
  func exportCalendarIcs(from: String?, to: String?) async throws -> String {
    try await service.exportCalendarICS(from: from, to: to)
  }
}
