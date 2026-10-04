import LorvexCore
import MCP

/// The `limit` and `offset` arguments every paged read tool shares. A limit is
/// at least 1 and at most the tool's maximum; an offset is at least 0 and at
/// most ``LorvexPageBounds/maximumOffset``, so any page arithmetic downstream
/// stays in range whatever integer an assistant sends.
enum PagingArguments {
  static func limit(
    _ arguments: [String: Value], default defaultLimit: Int, maximum: Int
  ) throws -> Int {
    let requested = try StrictScalarArguments.int(
      arguments["limit"], field: "limit", default: defaultLimit)
    return min(max(1, requested), maximum)
  }

  static func offset(_ arguments: [String: Value]) throws -> Int {
    LorvexPageBounds.clampedOffset(
      try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))
  }
}
