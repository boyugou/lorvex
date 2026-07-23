extension SwiftLorvexCoreService {
  /// Compute the `(returned, nextOffset, truncated)` pagination trio the app's
  /// page/search result types carry: `returned` is the page size, `nextOffset`
  /// is `offset + returned` when more rows exist, and `truncated` is set when
  /// the window did not exhaust `totalMatching`.
  static func pagination(
    returned: Int, totalMatching: Int, limit: Int, offset: Int
  ) -> (returned: Int, nextOffset: Int?, truncated: Bool) {
    let consumed = offset + returned
    let hasMore = consumed < totalMatching
    return (returned, hasMore ? consumed : nil, hasMore)
  }
}
