import MCP

extension ToolRegistry {
  /// Success envelope for a tool: a one-line human summary plus the complete
  /// structured payload. The current ``ToolDefinition`` applies its response
  /// fencing policy centrally on the way out, so the builder wraps `value`
  /// as-is.
  ///
  /// ``successResult(text:value:)`` names a mutation echo (the updated object);
  /// ``fencedReadResult(text:value:)`` names a read/query payload. The two share
  /// one shape — the distinct names mark caller intent, mirroring the central
  /// fencing that both rely on.
  func successResult(text: String, value: Value) -> CallTool.Result {
    CallTool.Result(
      content: [.text(text: text, annotations: nil, _meta: nil)],
      structuredContent: Optional.some(value),
      isError: false
    )
  }

  /// Read/query envelope: the summary plus the loaded structured payload. See
  /// ``successResult(text:value:)`` for the shared shape and the definition's
  /// central response-fencing policy that wraps every returned payload.
  func fencedReadResult(text: String, value: Value) -> CallTool.Result {
    CallTool.Result(
      content: [.text(text: text, annotations: nil, _meta: nil)],
      structuredContent: Optional.some(value),
      isError: false
    )
  }
}
