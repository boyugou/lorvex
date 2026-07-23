import MCP

/// The canonical pagination envelope shared by every paginated MCP read tool
/// (`list_tasks`, `search_tasks`, `get_deferred_tasks`, the calendar timeline,
/// `get_upcoming_tasks`, the reminder queries, `get_ai_changelog`,
/// `get_recent_logs`, and review history).
///
/// Every paginated response embeds these keys alongside its domain payload
/// (`tasks`, `events`, `entries`, `reminders`, `reviews`, …) so AI clients page
/// with one vocabulary:
///
///   total_matching · returned · limit · offset · next_offset · next_cursor · truncated
///
/// - `total_matching` is the full count of rows matching the query, or `null`
///   when the source cannot compute one (an append-only log paged by offset).
/// - `returned` is the number of rows in this page.
/// - `next_offset` is the offset to pass for the next page, or `null` at the end.
/// - `next_cursor` is reserved for future opaque-cursor pagination; it is always
///   `null` today. The key is present so clients can adopt cursors additively.
enum MCPPagination {
  /// Build the canonical envelope fields.
  static func envelope(
    totalMatching: Int?,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) -> [String: Value] {
    [
      "total_matching": totalMatching.map(Value.int) ?? .null,
      "returned": .int(returned),
      "limit": .int(limit),
      "offset": .int(offset),
      "next_offset": nextOffset.map(Value.int) ?? .null,
      "next_cursor": .null,
      "truncated": .bool(truncated),
    ]
  }

  /// Spread the canonical envelope into a fresh object alongside `domain` fields.
  static func object(
    domain: [String: Value],
    totalMatching: Int?,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) -> Value {
    .object(
      merged(
        into: domain, totalMatching: totalMatching, returned: returned, limit: limit,
        offset: offset, nextOffset: nextOffset, truncated: truncated))
  }

  /// Merge the canonical envelope into `object`.
  static func merged(
    into object: [String: Value],
    totalMatching: Int?,
    returned: Int,
    limit: Int,
    offset: Int,
    nextOffset: Int?,
    truncated: Bool
  ) -> [String: Value] {
    var result = object
    for (key, value) in envelope(
      totalMatching: totalMatching, returned: returned, limit: limit,
      offset: offset, nextOffset: nextOffset, truncated: truncated
    ) {
      result[key] = value
    }
    return result
  }
}
