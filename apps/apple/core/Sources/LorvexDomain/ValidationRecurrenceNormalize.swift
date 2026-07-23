/// Task and calendar recurrence-rule normalization.
///
/// ``ValidationRecurrence/normalizeTaskRecurrence(_:)`` is the single canonical
/// normalizer for task recurrence rules — every write surface stores the
/// returned canonical string. Output has stable key order (sorted by UTF-8 byte
/// via ``canonicalizeJSON(_:)``), defaults applied, and unknown keys rejected.
///
/// ``ValidationRecurrence/normalizeCalendarRecurrence(_:)`` delegates to the
/// task normalizer and layers two calendar-only rules on top: a tighter `COUNT`
/// cap and a stricter `BYDAY` policy on `MONTHLY` / `YEARLY`.

extension JSONValue {
  /// serde `Value::as_str`: the string payload, else `nil`.
  var asStr: String? {
    if case let .string(s) = self { return s }
    return nil
  }

  /// serde `Value::as_array`.
  var asArray: [JSONValue]? {
    if case let .array(a) = self { return a }
    return nil
  }

  /// serde `Value::as_object`.
  var asObject: [String: JSONValue]? {
    if case let .object(o) = self { return o }
    return nil
  }

  /// serde `Value::as_i64`: only integer literals in signed 64-bit range. Float
  /// literals (including `2.0`) and oversize unsigned integers return `nil`.
  var asI64: Int64? {
    switch self {
    case let .int(i): return i
    case let .uint(u): return u <= UInt64(Int64.max) ? Int64(u) : nil
    default: return nil
    }
  }

  /// Compact rendering used to fill the `actual` field of error
  /// messages. Reuses
  /// ``canonicalizeJSON(_:)`` so scalars and arrays render deterministically;
  /// falls back to a plain rendering if depth somehow overflows.
  var compactString: String {
    (try? canonicalizeJSON(self)) ?? "<unrenderable>"
  }
}

extension ValidationRecurrence {
  /// Known keys in the task recurrence JSON schema. Any other key is rejected.
  ///
  /// `ANCHOR` is a Lorvex extension (not RFC 5545): `"completion"` makes the
  /// next occurrence land INTERVAL units after the task is completed rather
  /// than on the fixed calendar cadence. It is omitted from canonical output
  /// for the default (`schedule`) so every existing fixed-cadence rule
  /// normalizes byte-identically.
  static let knownRecurrenceKeys: Set<String> = [
    "FREQ", "INTERVAL", "BYDAY", "BYMONTH", "BYMONTHDAY",
    "BYSETPOS", "WKST", "UNTIL", "COUNT", "ANCHOR",
  ]

  /// Validate and normalize a task recurrence rule string.
  ///
  /// Returns `.success(nil)` for empty/whitespace input (no recurrence),
  /// `.success(canonical)` for a valid rule, `.failure` on contract violation.
  /// Callers wanting non-fatal observations use
  /// ``normalizeTaskRecurrenceWithWarnings(_:)``.
  public static func normalizeTaskRecurrence(_ recurrence: String)
    -> Result<String?, ValidationError>
  {
    switch normalizeTaskRecurrenceWithWarnings(recurrence) {
    case let .success(outcome):
      return .success(outcome?.canonical)
    case let .failure(error):
      return .failure(error)
    }
  }

  /// A normalized recurrence rule and its non-fatal warnings.
  public struct NormalizedRecurrence: Sendable, Equatable {
    public let canonical: String
    public let warnings: [RecurrenceWarning]
  }

  /// Variant of ``normalizeTaskRecurrence(_:)`` that also returns any non-fatal
  /// ``RecurrenceWarning``s observed while validating the rule. Returns
  /// `.success(nil)` for empty/whitespace input.
  public static func normalizeTaskRecurrenceWithWarnings(_ recurrence: String)
    -> Result<NormalizedRecurrence?, ValidationError>
  {
    if ValidationFormat.trimWhitespace(recurrence).isEmpty {
      return .success(nil)
    }
    guard let parsed = JSONValue.parse(recurrence) else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "JSON object with FREQ field", actual: recurrence))
    }
    guard let obj = parsed.asObject else {
      return .failure(
        .invalidFormat(field: "recurrence", expected: "JSON object", actual: recurrence))
    }

    // Reject unknown keys. Iterate sorted keys so the cited key in the error is
    // deterministic (Swift dictionaries are unordered).
    for key in obj.keys.sorted() where !knownRecurrenceKeys.contains(key) {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected:
            "only FREQ/INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT keys allowed",
          actual: "unknown key '\(key)'"))
    }

    let freq: String
    switch parseFreq(parsed, recurrence: recurrence) {
    case let .success(v): freq = v
    case let .failure(e): return .failure(e)
    }
    let interval: Int64
    switch parseInterval(parsed) {
    case let .success(v): interval = v
    case let .failure(e): return .failure(e)
    }
    let byday: [String]?
    switch parseByday(parsed, freq: freq) {
    case let .success(v): byday = v
    case let .failure(e): return .failure(e)
    }
    let bysetpos: [Int64]?
    switch parseBysetpos(parsed, freq: freq) {
    case let .success(v): bysetpos = v
    case let .failure(e): return .failure(e)
    }
    let bymonth: [Int64]?
    switch parseBymonth(parsed, freq: freq) {
    case let .success(v): bymonth = v
    case let .failure(e): return .failure(e)
    }
    let wkst: String?
    switch parseWkst(parsed) {
    case let .success(v): wkst = v
    case let .failure(e): return .failure(e)
    }
    let bymonthday: [Int64]?
    switch parseBymonthday(parsed, freq: freq) {
    case let .success(v): bymonthday = v
    case let .failure(e): return .failure(e)
    }
    let until: String?
    switch parseUntil(parsed) {
    case let .success(v): until = v
    case let .failure(e): return .failure(e)
    }
    let count: Int64?
    switch parseCount(parsed) {
    case let .success(v): count = v
    case let .failure(e): return .failure(e)
    }
    let anchor: String?
    switch parseAnchor(parsed) {
    case let .success(v): anchor = v
    case let .failure(e): return .failure(e)
    }

    if count != nil && until != nil {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "COUNT and UNTIL are mutually exclusive",
          actual: "both COUNT and UNTIL present"))
    }

    // Build the canonical object. Key order in the output is determined by
    // canonicalizeJSON's UTF-8 byte sort, not insertion order, so insertion
    // order here is irrelevant to the byte output.
    var canonical: [String: JSONValue] = [:]
    canonical["FREQ"] = .string(freq)
    canonical["INTERVAL"] = .int(interval)
    if let days = byday { canonical["BYDAY"] = .array(days.map { .string($0) }) }
    if let months = bymonth { canonical["BYMONTH"] = .array(months.map { .int($0) }) }
    if let days = bymonthday { canonical["BYMONTHDAY"] = .array(days.map { .int($0) }) }
    if let positions = bysetpos { canonical["BYSETPOS"] = .array(positions.map { .int($0) }) }
    if let date = until { canonical["UNTIL"] = .string(date) }
    if let c = count { canonical["COUNT"] = .int(c) }
    if let start = wkst { canonical["WKST"] = .string(start) }
    // Only the non-default completion anchor is emitted; a schedule-anchored
    // rule omits ANCHOR so every existing fixed-cadence rule is byte-identical.
    if let a = anchor { canonical["ANCHOR"] = .string(a) }

    let warnings = emitWarnings(freq: freq, bymonthday: bymonthday, bymonth: bymonth)

    let rendered: String
    do {
      rendered = try canonicalizeJSON(.object(canonical))
    } catch {
      return .failure(.message("canonical recurrence not serializable: \(error)"))
    }
    return .success(NormalizedRecurrence(canonical: rendered, warnings: warnings))
  }

  // MARK: - Per-field parsers

  static func parseFreq(_ parsed: JSONValue, recurrence: String) -> Result<String, ValidationError> {
    guard let freq = parsed.asObject?["FREQ"]?.asStr else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "FREQ field (DAILY/WEEKLY/MONTHLY/YEARLY)",
          actual: recurrence))
    }
    if !validRecurrenceFreqs.contains(freq) {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "FREQ must be DAILY, WEEKLY, MONTHLY, or YEARLY",
          actual: freq))
    }
    return .success(freq)
  }

  static func parseInterval(_ parsed: JSONValue) -> Result<Int64, ValidationError> {
    let interval: Int64
    if let val = parsed.asObject?["INTERVAL"] {
      guard let i = val.asI64 else {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "INTERVAL must be a positive integer",
            actual: val.compactString))
      }
      interval = i
    } else {
      interval = 1
    }
    if interval < 1 {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "INTERVAL must be a positive integer",
          actual: String(interval)))
    }
    if interval > ValidationLimits.maxRecurrenceInterval {
      return .failure(
        .outOfRange(
          field: "recurrence", min: 1, max: ValidationLimits.maxRecurrenceInterval,
          actual: interval))
    }
    return .success(interval)
  }

  static func parseByday(_ parsed: JSONValue, freq: String) -> Result<[String]?, ValidationError> {
    guard let bydayVal = parsed.asObject?["BYDAY"] else { return .success(nil) }
    guard let arr = bydayVal.asArray else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "BYDAY must be an array of weekday codes",
          actual: bydayVal.compactString))
    }
    if !arr.isEmpty && !["WEEKLY", "MONTHLY", "YEARLY"].contains(freq) {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "BYDAY is only valid for WEEKLY, MONTHLY, or YEARLY recurrence",
          actual: "FREQ=\(freq) with BYDAY"))
    }
    var codes: [String] = []
    codes.reserveCapacity(arr.count)
    for code in arr {
      guard let s = code.asStr else {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "BYDAY elements must be strings",
            actual: code.compactString))
      }
      if !isValidBydayTokenForFreq(s, freq: freq) {
        let expected: String
        switch freq {
        case "WEEKLY":
          expected = "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU (WEEKLY rejects ordinal prefixes)"
        case "MONTHLY":
          expected =
            "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU, optionally prefixed with [+-]?1..=5 for MONTHLY"
        case "YEARLY":
          expected =
            "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU, optionally prefixed with [+-]?1..=53 for YEARLY"
        default:
          expected = "BYDAY codes must be MO/TU/WE/TH/FR/SA/SU"
        }
        return .failure(.invalidFormat(field: "recurrence", expected: expected, actual: s))
      }
      codes.append(s)
    }
    if codes.isEmpty { return .success(nil) }
    codes = sortDedupByday(codes)
    return .success(codes)
  }

  static func parseBysetpos(_ parsed: JSONValue, freq: String) -> Result<[Int64]?, ValidationError> {
    guard let val = parsed.asObject?["BYSETPOS"] else { return .success(nil) }
    if freq == "DAILY" || freq == "WEEKLY" {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "BYSETPOS is only supported for MONTHLY/YEARLY recurrence",
          actual: "FREQ=\(freq) with BYSETPOS"))
    }
    guard let arr = val.asArray else {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "BYSETPOS must be an array of integers in -366..=-1 ∪ 1..=366",
          actual: val.compactString))
    }
    var positions: [Int64] = []
    positions.reserveCapacity(arr.count)
    for item in arr {
      guard let n = item.asI64 else {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "BYSETPOS entries must be integers",
            actual: item.compactString))
      }
      if n == 0 || !(-366...366).contains(n) {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "BYSETPOS entries must be in -366..=-1 ∪ 1..=366",
            actual: String(n)))
      }
      positions.append(n)
    }
    if positions.isEmpty { return .success(nil) }
    positions.sort()
    positions = dedupSorted(positions)
    return .success(positions)
  }

  static func parseBymonth(_ parsed: JSONValue, freq: String) -> Result<[Int64]?, ValidationError> {
    guard let val = parsed.asObject?["BYMONTH"] else { return .success(nil) }
    if freq == "DAILY" {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "BYMONTH is only valid for WEEKLY/MONTHLY/YEARLY recurrence",
          actual: "FREQ=\(freq) with BYMONTH"))
    }
    switch parseIntArray(val, lo: 1, hi: 12) {
    case let .success(months):
      return .success(months.isEmpty ? nil : months)
    case let .failure(e):
      return .failure(e)
    }
  }

  static func parseWkst(_ parsed: JSONValue) -> Result<String?, ValidationError> {
    guard let val = parsed.asObject?["WKST"] else { return .success(nil) }
    guard let s = val.asStr else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "WKST must be a weekday code", actual: val.compactString))
    }
    if !isValidBydayCode(s) {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "WKST must be MO/TU/WE/TH/FR/SA/SU", actual: s))
    }
    return .success(s)
  }

  /// Parse `BYMONTHDAY` into a sorted, deduped array of month-days.
  ///
  /// Canonical output is always an array (`[1, 15]` — "1st and 15th of the
  /// month"), each entry in -31..=-1 ∪ 1..=31. A bare scalar (`15`) is accepted
  /// for back-compat with rules stored before the array form and normalizes to
  /// the single-element array `[15]`. An empty array is treated as absent
  /// (`nil`). Only valid on MONTHLY/YEARLY.
  static func parseBymonthday(_ parsed: JSONValue, freq: String) -> Result<[Int64]?, ValidationError> {
    guard let val = parsed.asObject?["BYMONTHDAY"] else { return .success(nil) }
    var days: [Int64] = []
    if let scalar = val.asI64 {
      days = [scalar]
    } else if let arr = val.asArray {
      days.reserveCapacity(arr.count)
      for item in arr {
        guard let n = item.asI64 else {
          return .failure(
            .invalidFormat(
              field: "recurrence", expected: "BYMONTHDAY entries must be integers",
              actual: item.compactString))
        }
        days.append(n)
      }
    } else {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "BYMONTHDAY must be an integer or array of integers in -31..=31, excluding 0",
          actual: val.compactString))
    }
    for day in days where day == 0 || !(-31...31).contains(day) {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "BYMONTHDAY must be an integer in -31..=31, excluding 0",
          actual: String(day)))
    }
    if days.isEmpty { return .success(nil) }
    if freq != "MONTHLY" && freq != "YEARLY" {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "BYMONTHDAY is only valid for MONTHLY/YEARLY recurrence",
          actual: "FREQ=\(freq) with BYMONTHDAY"))
    }
    days.sort()
    return .success(dedupSorted(days))
  }

  static func parseUntil(_ parsed: JSONValue) -> Result<String?, ValidationError> {
    guard let val = parsed.asObject?["UNTIL"] else { return .success(nil) }
    guard let s = val.asStr else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "UNTIL must be a YYYY-MM-DD or RFC5545 DATE-TIME string",
          actual: val.compactString))
    }
    guard let canonical = IsoDate.parseUntilToYmd(s) else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "UNTIL must be YYYY-MM-DD, YYYYMMDD, or YYYYMMDDTHHMMSSZ",
          actual: s))
    }
    return .success(canonical)
  }

  static func parseCount(_ parsed: JSONValue) -> Result<Int64?, ValidationError> {
    guard let val = parsed.asObject?["COUNT"] else { return .success(nil) }
    guard let c = val.asI64 else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "COUNT must be a positive integer",
          actual: val.compactString))
    }
    if c < 1 {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "COUNT must be a positive integer", actual: String(c)))
    }
    return .success(c)
  }

  /// Parse the Lorvex `ANCHOR` extension. Accepts `"schedule"` (the default,
  /// returned as `nil` so it is omitted from canonical output) or
  /// `"completion"`. Completion-anchored rules are incompatible with positional
  /// scheduling (`BYDAY`/`BYMONTH`/`BYMONTHDAY`/`BYSETPOS`/`WKST`): the next
  /// occurrence is INTERVAL units after completion, so a fixed weekday/month
  /// has no meaning and is rejected rather than silently ignored.
  static func parseAnchor(_ parsed: JSONValue) -> Result<String?, ValidationError> {
    guard let val = parsed.asObject?["ANCHOR"] else { return .success(nil) }
    guard let s = val.asStr else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "ANCHOR must be \"schedule\" or \"completion\"",
          actual: val.compactString))
    }
    switch s {
    case "schedule":
      return .success(nil)
    case "completion":
      let obj = parsed.asObject ?? [:]
      for key in ["BYDAY", "BYMONTH", "BYMONTHDAY", "BYSETPOS", "WKST"] where obj[key] != nil {
        return .failure(
          .invalidFormat(
            field: "recurrence",
            expected: "ANCHOR=completion repeats INTERVAL units after completion and cannot combine with positional keys",
            actual: "\(key) with ANCHOR=completion"))
      }
      return .success("completion")
    default:
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "ANCHOR must be \"schedule\" or \"completion\"", actual: s))
    }
  }

  // MARK: - Helpers

  /// Parse a JSON array of integers constrained to `lo...hi`, then sort + dedup
  /// so logically-identical rules converge on byte-identical canonical JSON.
  /// Error text is pinned to the `BYMONTH` wording (the only current caller).
  static func parseIntArray(_ val: JSONValue, lo: Int64, hi: Int64)
    -> Result<[Int64], ValidationError>
  {
    guard let arr = val.asArray else {
      return .failure(
        .invalidFormat(
          field: "recurrence", expected: "BYMONTH must be an array of integers in 1..=12",
          actual: val.compactString))
    }
    var out: [Int64] = []
    out.reserveCapacity(arr.count)
    for item in arr {
      guard let n = item.asI64 else {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "BYMONTH entries must be integers",
            actual: item.compactString))
      }
      if !(lo...hi).contains(n) {
        return .failure(
          .invalidFormat(
            field: "recurrence", expected: "BYMONTH entries must be in 1..=12", actual: String(n)))
      }
      out.append(n)
    }
    out.sort()
    return .success(dedupSorted(out))
  }

  /// Canonical sort key for a single BYDAY token: `(ordinal, weekdayIndex)`,
  /// `ordinal` defaulting to 0 for an unprefixed token and `weekdayIndex`
  /// following MO=0..SU=6. Unparseable tokens sort to the tail `(Int.max, 7)`.
  static func canonicalBydaySortKey(_ token: String) -> (Int, Int) {
    let bytes = Array(token.utf8)
    if bytes.count < 2 { return (Int.max, 7) }
    let split = bytes.count - 2
    guard let code = String(bytes: bytes[split...], encoding: .utf8) else { return (Int.max, 7) }
    let weekday: Int
    switch code {
    case "MO": weekday = 0
    case "TU": weekday = 1
    case "WE": weekday = 2
    case "TH": weekday = 3
    case "FR": weekday = 4
    case "SA": weekday = 5
    case "SU": weekday = 6
    default: return (Int.max, 7)
    }
    let prefixBytes = bytes[..<split]
    let ordinal: Int
    if prefixBytes.isEmpty {
      ordinal = 0
    } else if let s = String(bytes: prefixBytes, encoding: .utf8), let v = Int(s) {
      ordinal = v
    } else {
      ordinal = Int.max
    }
    return (ordinal, weekday)
  }

  /// Stable sort by ``canonicalBydaySortKey(_:)`` followed by adjacent dedup.
  static func sortDedupByday(_ codes: [String]) -> [String] {
    let sorted = codes.enumerated().sorted { lhs, rhs in
      let lk = canonicalBydaySortKey(lhs.element)
      let rk = canonicalBydaySortKey(rhs.element)
      if lk != rk { return lk < rk }
      return lhs.offset < rhs.offset  // preserve input order on ties (stable)
    }.map { $0.element }
    var out: [String] = []
    for c in sorted where out.last != c { out.append(c) }
    return out
  }

  /// Adjacent dedup of an already-sorted integer array.
  static func dedupSorted(_ xs: [Int64]) -> [Int64] {
    var out: [Int64] = []
    for x in xs where out.last != x { out.append(x) }
    return out
  }

  /// Emit non-fatal warnings for an already-validated rule: each positive
  /// `BYMONTHDAY` in 29…31 on MONTHLY/YEARLY skips short months (one warning per
  /// such day, in canonical order), and the leap-year birthday shape
  /// (`FREQ=YEARLY;BYMONTH=[2];BYMONTHDAY=[29]`) suppresses that generic warning
  /// in favor of ``RecurrenceWarning/leapYearBirthday``.
  static func emitWarnings(freq: String, bymonthday: [Int64]?, bymonth: [Int64]?)
    -> [RecurrenceWarning]
  {
    var warnings: [RecurrenceWarning] = []
    guard freq == "MONTHLY" || freq == "YEARLY" else { return warnings }
    guard let days = bymonthday else { return warnings }
    for day in days where (29...31).contains(day) {
      warnings.append(.bymonthdaySkipsMonths(day: day))
    }
    // The single-day Feb-29 yearly birthday collapses the generic skip warning
    // into the more specific leapYearBirthday. A multi-day rule keeps the
    // per-day skip warnings.
    if freq == "YEARLY", days == [29] {
      if let months = bymonth, months.count == 1, months[0] == 2 {
        warnings.removeAll {
          if case .bymonthdaySkipsMonths = $0 { return true }
          return false
        }
        warnings.append(.leapYearBirthday)
      }
    }
    return warnings
  }

  // MARK: - Calendar normalizer

  /// Calendar-event recurrence normalizer.
  ///
  /// Returns `.success(nil)` for `nil`/empty/whitespace input,
  /// `.success(canonical)` on valid input, `.failure` on contract violation.
  /// Layers three calendar-only rules over ``normalizeTaskRecurrence(_:)``:
  /// 1. A bare FREQ word (`"WEEKLY"`) is accepted as shorthand and wrapped to
  ///    `{"FREQ":"WEEKLY","INTERVAL":1}` before delegation.
  /// 2. `COUNT` is capped at ``maxCalendarRecurrenceCount`` (365).
  /// 3. `MONTHLY` / `YEARLY` with a bare two-letter `BYDAY` code (no ordinal
  ///    prefix) is rejected unless `BYSETPOS` is also present.
  public static func normalizeCalendarRecurrence(_ raw: String?)
    -> Result<String?, ValidationError>
  {
    guard let raw = raw else { return .success(nil) }
    let trimmed = ValidationFormat.trimWhitespace(raw)
    if trimmed.isEmpty { return .success(nil) }

    let canonicalInput: String
    if isValidRecurrenceFreq(trimmed) {
      // Wrap to a canonical object. canonicalizeJSON sorts keys, so this yields
      // {"FREQ":"…","INTERVAL":1}.
      canonicalInput =
        (try? canonicalizeJSON(.object(["FREQ": .string(trimmed), "INTERVAL": .int(1)]))) ?? trimmed
    } else {
      canonicalInput = trimmed
    }

    let normalized: String
    switch normalizeTaskRecurrence(canonicalInput) {
    case let .success(opt):
      guard let value = opt else { return .failure(.empty("recurrence")) }
      normalized = value
    case let .failure(e):
      return .failure(e)
    }

    guard let parsed = JSONValue.parse(normalized), let obj = parsed.asObject else {
      return .failure(.message("canonical recurrence not parseable post-normalization"))
    }

    if obj["ANCHOR"] != nil {
      return .failure(
        .invalidFormat(
          field: "recurrence",
          expected: "ANCHOR=completion is a task-only concept; calendar events have no completion",
          actual: "ANCHOR on calendar recurrence"))
    }

    if let count = obj["COUNT"]?.asI64, count > maxCalendarRecurrenceCount {
      return .failure(
        .outOfRange(
          field: "recurrence.COUNT", min: 1, max: maxCalendarRecurrenceCount, actual: count))
    }

    if let freq = obj["FREQ"]?.asStr, freq == "MONTHLY" || freq == "YEARLY" {
      if let byday = obj["BYDAY"]?.asArray {
        let hasBysetpos = obj["BYSETPOS"] != nil
        if !hasBysetpos {
          for code in byday {
            let s = code.asStr ?? ""
            if s.utf8.count == 2 {
              return .failure(
                .message(
                  "recurrence.BYDAY \"\(s)\" is only valid for WEEKLY; "
                    + "for FREQ=\(freq) prefix the day with an ordinal "
                    + "(e.g. \"1MO\" for first Monday, \"-1FR\" for last Friday) "
                    + "or pair BYDAY with BYSETPOS"))
            }
          }
        }
      }
    }

    return .success(normalized)
  }

  /// Validate the anchor-dependent bound of an already-normalized calendar
  /// recurrence. `UNTIL` is inclusive, so equality with `startDate` is valid;
  /// a date before the first occurrence would create a series that can never
  /// fire and is rejected consistently by every write boundary.
  public static func validateCalendarRecurrenceBound(
    _ normalized: String?, startDate: LorvexDate
  ) -> Result<Void, ValidationError> {
    guard let normalized else { return .success(()) }
    guard let parsed = JSONValue.parse(normalized), let object = parsed.asObject else {
      return .failure(.message("canonical recurrence not parseable post-normalization"))
    }
    guard let rawUntil = object["UNTIL"]?.asStr else { return .success(()) }
    guard case let .success(until) = LorvexDate.parse(rawUntil) else {
      return .failure(
        .invalidFormat(
          field: "recurrence.UNTIL", expected: "canonical YYYY-MM-DD", actual: rawUntil))
    }
    if until < startDate {
      return .failure(
        .message(
          "recurrence.UNTIL (\(until.asString)) cannot be before start_date (\(startDate.asString))"
        ))
    }
    return .success(())
  }
}
