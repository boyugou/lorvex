import Foundation
import MCP

extension ToolRegistry {
  /// The key of the structured payload's list of notes for the caller.
  static let warningsKey = "warnings"

  /// `result` as it leaves the server, with everything meant for the model in
  /// both places a client may read.
  ///
  /// Clients differ in what they hand the model: some pass only
  /// `structuredContent`, some only the text in `content`. So a note about
  /// ignored arguments joins the structured payload under ``warningsKey``, and
  /// `content` ends with a text block holding the structured payload as JSON,
  /// which the MCP specification asks of a tool that returns structured
  /// content. A result whose structured payload is not an object carries the
  /// note as a text block instead.
  static func delivering(_ result: CallTool.Result, for params: CallTool.Parameters)
    -> CallTool.Result
  {
    var content = result.content
    var structured = result.structuredContent
    if let note = undeclaredArgumentsNote(for: params) {
      if case .object(var payload)? = structured {
        payload[warningsKey] = .array((payload[warningsKey]?.arrayValue ?? []) + [.string(note)])
        structured = .object(payload)
      } else {
        content.append(.text(text: note, annotations: nil, _meta: nil))
      }
    }
    if let structured, let json = serializedJSON(structured) {
      content.append(.text(text: json, annotations: nil, _meta: nil))
    }
    return CallTool.Result(
      content: content, structuredContent: structured, isError: result.isError,
      _meta: result._meta)
  }

  /// `value` as compact JSON with its keys in order, or nil when it cannot be
  /// encoded.
  static func serializedJSON(_ value: Value) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
