/// Bounds that every paged read applies to the window its caller asks for.
public enum LorvexPageBounds {
  /// The largest offset a paged read honors. It is far past any collection the
  /// app stores, so a larger offset reads as "past the end" and selects an empty
  /// page, and adding a page size to an offset can never overflow.
  public static let maximumOffset = 1_000_000

  /// `offset` limited to `0...maximumOffset`.
  public static func clampedOffset(_ offset: Int) -> Int {
    min(max(offset, 0), maximumOffset)
  }
}
