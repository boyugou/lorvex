/// Typed errors raised by the runtime operating-model surfaces.
public enum RuntimeError: Error, Equatable {
  /// `local_counters.value` is `INTEGER NOT NULL`; a negative read indicates
  /// on-disk corruption that broke the monotonicity invariant callers depend
  /// on. Surfaced as a typed error rather than silently truncated to a fresh
  /// zero counter. The associated value is the corrupt value rendered as its
  /// decimal string.
  case corruptLocalChangeSeq(String)
}
