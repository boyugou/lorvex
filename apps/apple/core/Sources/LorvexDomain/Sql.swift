/// SQL placeholder string builders shared by store + sync.
public enum Sql {
  /// Comma-separated numbered SQL positional placeholders.
  ///
  /// Use when the surrounding statement mixes the IN list with other
  /// `?N`-bound parameters and the explicit numbering keeps the bind
  /// table readable. For an IN list whose binds are just the contents of
  /// the iterator (no leading params), prefer ``sqlCsvPlaceholders(_:)``.
  ///
  /// Examples: `sqlInPlaceholders(3, 0) == "?1, ?2, ?3"`,
  /// `sqlInPlaceholders(2, 5) == "?6, ?7"`, `sqlInPlaceholders(0, 0) == ""`.
  public static func sqlInPlaceholders(_ count: Int, _ offset: Int) -> String {
    if count == 0 { return "" }
    var out = ""
    out.reserveCapacity(count * 5)
    for i in 0..<count {
      if i > 0 { out += ", " }
      out += "?\(offset + i + 1)"
    }
    return out
  }

  /// Comma-separated unnumbered SQL placeholders (`?, ?, ?`) for an
  /// `IN (...)` clause bound via `params_from_iter` shapes.
  ///
  /// Pre-allocates the exact byte length up-front: each placeholder is `?`
  /// plus a `, ` separator (except the last), so the buffer length is
  /// `3 * count - 2` for `count >= 1` and `0` otherwise.
  public static func sqlCsvPlaceholders(_ count: Int) -> String {
    if count == 0 { return "" }
    var out = ""
    out.reserveCapacity(3 * count - 2)
    out.append("?")
    for _ in 1..<count {
      out.append(", ?")
    }
    return out
  }
}
