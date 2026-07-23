import Foundation

/// Canonical typed wrapper around a UTC instant rendered in the canonical
/// sync-timestamp wire form: RFC 3339, **millisecond** precision, trailing `Z`
/// (`YYYY-MM-DDTHH:MM:SS.mmmZ`, exactly 24 characters).
///
/// Ordering is instant-backed (byte-compares become value-compares), and the
/// only way to produce one is ``now()`` / ``init(date:)`` / ``parse(_:)`` — every
/// constructor renders through ``SyncTimestampFormat/format(_:)``, so the
/// canonical shape is type-system enforced. JSON encoding preserves the same
/// canonical string.
///
/// The fixed millisecond precision matches SQLite's
/// `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')` and the CloudKit record format, so
/// lexicographic comparisons against peer-emitted timestamps stay correct
/// regardless of the precision a peer happened to render.
public struct SyncTimestamp: Sendable, Equatable, Hashable, Comparable, Codable {
  /// The instant truncated to whole milliseconds (the canonical form carries no
  /// finer precision, so equality / ordering must compare at that resolution).
  let epochMilliseconds: Int64

  init(epochMilliseconds: Int64) {
    self.epochMilliseconds = epochMilliseconds
  }

  /// Wrap a `Foundation.Date` (interpreted as a UTC instant), truncating to
  /// millisecond precision to match the rendered canonical form.
  public init(date: Date) {
    self.epochMilliseconds = SyncTimestampFormat.epochMillis(from: date)
  }

  /// Capture the current wall clock as a canonical sync timestamp.
  public static func now() -> SyncTimestamp {
    SyncTimestamp(date: Date())
  }

  /// The instant as a `Foundation.Date`, at the canonical millisecond
  /// resolution. Use when a caller needs to re-project the instant into a
  /// local calendar (e.g. folding a completion timestamp to its local day).
  public var date: Date {
    Date(timeIntervalSince1970: Double(epochMilliseconds) / 1000.0)
  }

  /// Owned canonical-form rendering (`YYYY-MM-DDTHH:MM:SS.mmmZ`).
  public var asString: String {
    SyncTimestampFormat.format(epochMilliseconds: epochMilliseconds)
  }

  /// Parse a sync timestamp from the canonical wire form. Accepts any
  /// second/ms/µs-precision RFC 3339 string with a UTC offset (`Z` or `+00:00`)
  /// and re-renders at canonical millisecond precision. Rejects non-UTC offsets.
  public static func parse(_ raw: String) -> SyncTimestamp? {
    guard let parsed = SyncTimestampFormat.parseRfc3339(raw), parsed.offsetSeconds == 0 else {
      return nil
    }
    return SyncTimestamp(epochMilliseconds: parsed.epochMilliseconds)
  }

  public static func < (lhs: SyncTimestamp, rhs: SyncTimestamp) -> Bool {
    lhs.epochMilliseconds < rhs.epochMilliseconds
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let ts = SyncTimestamp.parse(raw) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription:
            "invalid sync timestamp: expected RFC 3339 with a UTC offset (`Z` or `+00:00`)"))
    }
    self = ts
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(asString)
  }
}

/// RFC 3339 / canonical sync-timestamp string functions (the `format_*` /
/// `normalize_*` family). All math runs on a proleptic-Gregorian UTC calendar
/// so output is deterministic regardless of the host time zone.
public enum SyncTimestampFormat {
  static let utcCalendar: Calendar = IsoDate.calendar

  /// Whole milliseconds since the Unix epoch, rounding toward negative infinity
  /// so sub-millisecond fractions never round a timestamp forward.
  static func epochMillis(from date: Date) -> Int64 {
    let seconds = date.timeIntervalSince1970
    return Int64((seconds * 1000.0).rounded(.down))
  }

  /// Canonical millisecond-precision render of the current wall clock.
  public static func syncTimestampNow() -> String {
    format(epochMilliseconds: epochMillis(from: Date()))
  }

  /// Format a `Foundation.Date` (UTC instant) in the canonical sync-timestamp
  /// shape.
  public static func formatSyncTimestamp(_ date: Date) -> String {
    format(epochMilliseconds: epochMillis(from: date))
  }

  /// Canonicalize a user-supplied RFC 3339 instant into the stored sync-timestamp
  /// form. Unlike ``normalizeSyncTimestamp(_:)`` this accepts non-UTC offsets and
  /// converts them to UTC.
  public static func canonicalizeRfc3339Instant(_ raw: String) -> String? {
    guard let parsed = parseRfc3339(raw) else { return nil }
    return format(epochMilliseconds: parsed.epochMilliseconds)
  }

  /// Normalize an RFC 3339 UTC timestamp to the canonical millisecond form.
  /// Rejects non-UTC offsets.
  public static func normalizeSyncTimestamp(_ raw: String) -> String? {
    guard let parsed = parseRfc3339(raw), parsed.offsetSeconds == 0 else { return nil }
    return format(epochMilliseconds: parsed.epochMilliseconds)
  }

  /// Render whole milliseconds since epoch as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
  static func format(epochMilliseconds: Int64) -> String {
    let wholeSeconds = Int(floorDiv(epochMilliseconds, 1000))
    let millis = Int(epochMilliseconds - Int64(wholeSeconds) * 1000)
    let date = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
    let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis)
  }

  static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
  }

  /// Parsed RFC 3339 result: the instant in whole milliseconds since epoch and
  /// the source offset in seconds (`0` for `Z` / `+00:00`).
  struct Parsed {
    let epochMilliseconds: Int64
    let offsetSeconds: Int
  }

  /// Strict RFC 3339 date-time parser sufficient for sync timestamps:
  /// `YYYY-MM-DDTHH:MM:SS[.fraction]<offset>` where offset is `Z`, `z`, or
  /// `±HH:MM`. The `T` separator may also be a space (RFC 3339 §5.6 allows it).
  /// Fractional seconds of any digit count are accepted and truncated to
  /// milliseconds. Returns `nil` on any deviation.
  static func parseRfc3339(_ raw: String) -> Parsed? {
    let chars = Array(raw)
    guard chars.count >= 20 else { return nil }
    // date: YYYY-MM-DD
    func d(_ i: Int) -> Int? {
      let c = chars[i]
      guard c.isASCII, let v = c.wholeNumberValue, c.isNumber else { return nil }
      return v
    }
    guard chars[4] == "-", chars[7] == "-" else { return nil }
    guard let y0 = d(0), let y1 = d(1), let y2 = d(2), let y3 = d(3),
      let mo0 = d(5), let mo1 = d(6), let da0 = d(8), let da1 = d(9)
    else { return nil }
    let sep = chars[10]
    guard sep == "T" || sep == "t" || sep == " " else { return nil }
    guard chars[13] == ":", chars[16] == ":" else { return nil }
    guard let h0 = d(11), let h1 = d(12), let mi0 = d(14), let mi1 = d(15),
      let s0 = d(17), let s1 = d(18)
    else { return nil }
    let year = y0 * 1000 + y1 * 100 + y2 * 10 + y3
    let month = mo0 * 10 + mo1
    let day = da0 * 10 + da1
    let hour = h0 * 10 + h1
    let minute = mi0 * 10 + mi1
    let second = s0 * 10 + s1
    guard (1...12).contains(month), (1...31).contains(day),
      (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
    else { return nil }

    // optional fraction, then offset
    var idx = 19
    var fractionMillis = 0
    if idx < chars.count, chars[idx] == "." {
      idx += 1
      var fracDigits = [Int]()
      while idx < chars.count, let v = chars[idx].wholeNumberValue, chars[idx].isNumber, chars[idx].isASCII {
        fracDigits.append(v)
        idx += 1
      }
      guard !fracDigits.isEmpty else { return nil }
      // truncate to milliseconds (first 3 digits, zero-padded)
      for k in 0..<3 {
        fractionMillis = fractionMillis * 10 + (k < fracDigits.count ? fracDigits[k] : 0)
      }
    }

    // offset
    var offsetSeconds = 0
    guard idx < chars.count else { return nil }
    let oc = chars[idx]
    if oc == "Z" || oc == "z" {
      idx += 1
    } else if oc == "+" || oc == "-" {
      // ±HH:MM
      guard idx + 6 <= chars.count else { return nil }
      let signNeg = oc == "-"
      idx += 1
      func od(_ j: Int) -> Int? {
        let c = chars[j]
        guard c.isASCII, c.isNumber, let v = c.wholeNumberValue else { return nil }
        return v
      }
      guard let oh0 = od(idx), let oh1 = od(idx + 1) else { return nil }
      guard chars[idx + 2] == ":" else { return nil }
      guard let om0 = od(idx + 3), let om1 = od(idx + 4) else { return nil }
      let offH = oh0 * 10 + oh1
      let offM = om0 * 10 + om1
      guard (0...23).contains(offH), (0...59).contains(offM) else { return nil }
      offsetSeconds = (offH * 3600 + offM * 60) * (signNeg ? -1 : 1)
      idx += 5
    } else {
      return nil
    }
    guard idx == chars.count else { return nil }

    var dc = DateComponents()
    dc.year = year
    dc.month = month
    dc.day = day
    dc.hour = hour
    dc.minute = minute
    dc.second = second
    guard let date = utcCalendar.date(from: dc) else { return nil }
    // Validate the date round-trips (rejects 2026-13-01 etc.).
    let back = utcCalendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == year, back.month == month, back.day == day else { return nil }
    let utcEpochMs = Int64((date.timeIntervalSince1970).rounded(.down)) * 1000 + Int64(fractionMillis)
    // Subtract the source offset to get the true UTC instant.
    let epochMs = utcEpochMs - Int64(offsetSeconds) * 1000
    return Parsed(epochMilliseconds: epochMs, offsetSeconds: offsetSeconds)
  }
}
