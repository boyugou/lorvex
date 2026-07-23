import Foundation

/// Canonical handling of the `working_hours` preference value
/// (`{"start":"HH:MM","end":"HH:MM"}`): parsing, validation, and encoding
/// shared by every settings surface. The engine default is 09:00-18:00.
public enum WorkingHoursPreference {
  public static let defaultWindow = (start: "09:00", end: "18:00")

  /// Stored JSON → window; nil when absent or malformed.
  public static func parse(_ raw: String?) -> (start: String, end: String)? {
    guard let raw, let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let start = object["start"], let end = object["end"]
    else { return nil }
    return (start, end)
  }

  /// User-facing input → canonical stored JSON. Accepts the canonical JSON
  /// object and the shorthand `HH:MM-HH:MM`, but callers should only persist the
  /// returned JSON so every read surface sees the same shape.
  public static func canonicalStoredValue(from raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let parsed = parse(trimmed) {
      return encode(start: parsed.start, end: parsed.end)
    }
    let parts = trimmed.split(separator: "-", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    return encode(start: parts[0], end: parts[1])
  }

  /// Window → stored JSON; nil for malformed times or an end at/before the
  /// start, which callers surface as a validation error.
  public static func encode(start: String, end: String) -> String? {
    guard let startMinutes = minutesOfDay(start), let endMinutes = minutesOfDay(end),
      endMinutes > startMinutes
    else { return nil }
    return #"{"start":"\#(start)","end":"\#(end)"}"#
  }

  public static func minutesOfDay(_ value: String) -> Int? {
    let parts = value.split(separator: ":")
    guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
      (0...23).contains(hours), (0...59).contains(minutes)
    else { return nil }
    return hours * 60 + minutes
  }
}
