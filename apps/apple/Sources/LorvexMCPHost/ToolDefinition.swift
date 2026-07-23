import MCP

/// One public MCP tool's complete runtime wiring.
///
/// The catalog-owned ``Tool`` remains the wire-schema authority. This value
/// binds that exact schema object to its handler and the cross-cutting policies
/// that dispatch must enforce, so listing and invocation cannot drift apart.
struct ToolDefinition: Sendable {
  typealias Handler =
    @Sendable (ToolRegistry, [String: Value]) async throws -> CallTool.Result

  enum Idempotency: Sendable {
    /// Read-only and snapshot-producing tools never cache responses.
    case none

    /// The write accepts an optional client key. A present non-empty key makes
    /// identical retries replay-safe and rejects checksum mismatches.
    case optionalClientKey
  }

  enum Access: Sendable {
    case read
    case write(idempotency: Idempotency)
  }

  let listingOrder: Int
  let tool: Tool
  let access: Access
  let responseFencing: ToolResponseFencing
  let handler: Handler

  static func read(
    _ listingOrder: Int,
    _ tool: Tool,
    responseFencing: ToolResponseFencing = .userControlledContent,
    handler: @escaping Handler
  ) -> Self {
    Self(
      listingOrder: listingOrder,
      tool: tool,
      access: .read,
      responseFencing: responseFencing,
      handler: handler
    )
  }

  static func write(
    _ listingOrder: Int,
    _ tool: Tool,
    responseFencing: ToolResponseFencing = .userControlledContent,
    handler: @escaping Handler
  ) -> Self {
    Self(
      listingOrder: listingOrder,
      tool: tool,
      access: .write(idempotency: .optionalClientKey),
      responseFencing: responseFencing,
      handler: handler
    )
  }

  var isWrite: Bool {
    switch access {
    case .read: false
    case .write: true
    }
  }

  var participatesInIdempotency: Bool {
    switch access {
    case .read:
      false
    case .write(let idempotency):
      switch idempotency {
      case .none: false
      case .optionalClientKey: true
      }
    }
  }

  func call(
    on registry: ToolRegistry,
    arguments: [String: Value]
  ) async throws -> CallTool.Result {
    let result = try await handler(registry, arguments)
    return responseFencing.apply(to: result)
  }
}

/// Describes which portions of a tool response can contain user-authored text.
/// Every current tool uses the same policy, but the policy lives on each
/// definition so a future machine-only response can opt out without adding a
/// parallel dispatch allowlist.
struct ToolResponseFencing: Sendable {
  let stringFields: Set<String>
  let stringArrayFields: Set<String>
  let fenceTextContent: Bool

  static let userControlledContent = Self(
    stringFields: SecurityFencing.userContentKeys,
    stringArrayFields: SecurityFencing.userContentArrayKeys,
    fenceTextContent: true
  )

  func apply(to result: CallTool.Result) -> CallTool.Result {
    let content = result.content.map { item in
      guard fenceTextContent else { return item }
      switch item {
      case .text(let text, let annotations, let meta):
        return .text(
          text: SecurityFencing.fence(text),
          annotations: annotations,
          _meta: meta
        )
      default:
        return item
      }
    }

    guard let structured = result.structuredContent else {
      return CallTool.Result(
        content: content,
        structuredContent: nil,
        isError: result.isError
      )
    }
    return CallTool.Result(
      content: content,
      structuredContent: Optional.some(
        SecurityFencing.fenceValue(
          structured,
          stringFields: stringFields,
          stringArrayFields: stringArrayFields
        )
      ),
      isError: result.isError
    )
  }
}
