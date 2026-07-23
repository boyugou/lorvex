import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func exportDataResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let request: DataExportToolRequest
    do {
      request = try DataExportToolRequest(arguments: arguments)
    } catch let error as DataExportToolRequest.ValidationError {
      return Self.errorResult(code: "validation", message: error.message, toolName: "export_data")
    }
    guard request.hasExplicitEntities else {
      return Self.errorResult(
        code: "validation",
        message: "Pass entities explicitly, for example [\"tasks\"] or [\"all\"].",
        toolName: "export_data")
    }
    // Uses the full-read exporter with its AI audience projection. All selected
    // categories stay complete except provider focus blocks, which honor the
    // device-local calendar AI-access tier (`off` omits them). Human-initiated
    // Settings/App-Intent backups retain the ordinary complete-export path.
    // Source identity is threaded through for the JSON provenance manifest.
    let output = try await coreBridge.service.exportDataForAI(
      entities: request.entityList,
      format: request.format.rawValue,
      appVersion: LorvexProductMetadata.marketingVersion,
      generatedAt: LorvexDateFormatters.iso8601.string(from: Date()))
    var structured = ExportFileMetadata.data(format: request.format)
    let resourceURI = structured["resource_uri"]?.stringValue ?? "lorvex://exports/lorvex-export"
    structured["format"] = .string(request.format.rawValue)
    structured["byte_count"] = .int(output.utf8.count)
    return CallTool.Result(
      content: [
        .text(
          text: "Export prepared as \(request.format.rawValue). See the embedded resource.",
          annotations: nil,
          _meta: nil),
        // Keep the exact downloadable bytes while preventing user-authored
        // fields in the export from becoming model-facing prompt text. MCP blob
        // resources are base64 on the wire and explicitly user-only.
        .resource(
          resource: .binary(
            Data(output.utf8),
            uri: resourceURI,
            mimeType: structured["content_type"]?.stringValue),
          annotations: .init(audience: [.user]),
          _meta: nil)
      ],
      structuredContent: Optional.some(.object(structured)),
      isError: false
    )
  }
}
