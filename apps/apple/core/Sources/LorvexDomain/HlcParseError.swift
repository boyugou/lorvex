/// Parse error variants for HLC strings.
///
/// Variant identity must be preserved so callers can pattern-match on parse
/// failures (e.g. the sync apply pipeline routes corrupt-suffix envelopes to
/// the pending-inbox / conflict-log diagnostics distinctly from clock-skew
/// out-of-range ones).
public enum HlcParseError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidFormat(String)
  case invalidPhysicalMs(String)
  /// `physicalMs` exceeds `Hlc.maxPhysicalMs` (~year 2286). Refused so a
  /// clock-skewed peer can't poison cluster-wide LWW by emitting a value
  /// that lex-sorts above every legitimate 13-digit HLC forever.
  case physicalMsOutOfRange(UInt64)
  case invalidCounter(String)
  /// `counter` exceeds `Hlc.maxCounter` (9999). Refused so the canonical
  /// `{:04}` slot can't widen to five digits and break raw string ordering.
  case counterOutOfRange(UInt32)
  case emptyDeviceSuffix
  case invalidDeviceSuffixLength(suffix: String, expected: Int, actual: Int)
  case invalidDeviceSuffixCharset(String)

  public var description: String {
    switch self {
    case .invalidFormat(let s): return "invalid HLC format: \(s)"
    case .invalidPhysicalMs(let s): return "invalid physical_ms: \(s)"
    case .physicalMsOutOfRange(let ms):
      return "physical_ms \(ms) exceeds maximum \(Hlc.maxPhysicalMs) (~year 2286)"
    case .invalidCounter(let s): return "invalid counter: \(s)"
    case .counterOutOfRange(let c):
      return
        "counter \(c) exceeds maximum \(Hlc.maxCounter) (canonical HLC counter range is 0000-9999)"
    case .emptyDeviceSuffix: return "empty device suffix"
    case .invalidDeviceSuffixLength(let s, let expected, let actual):
      return "device suffix \"\(s)\" length \(actual) does not match required \(expected)"
    case .invalidDeviceSuffixCharset(let s):
      return "device suffix \"\(s)\" contains non-hex characters (must be lowercase ascii hex)"
    }
  }
}
