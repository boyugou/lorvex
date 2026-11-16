import Foundation
import LorvexDomain

/// An authoritative provider occurrence. `date` is its source-calendar slot,
/// independent of the display zone; instants disambiguate repeated clocks.
/// Only occupancy is stored here, so this survives the busy-only privacy tier.
public struct ProviderOccurrenceInstant: Sendable, Equatable, Hashable, Codable {
  public let date: String
  public let start: Date
  public let end: Date?

  public init(date: String, start: Date, end: Date?) {
    self.date = date
    self.start = start
    self.end = end
  }

  /// Stable encoding prevents equivalent enumerations from reporting a change.
  static func encode(_ occurrences: [Self]) -> String? {
    let sorted = Set(occurrences).sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.start != $1.start { return $0.start < $1.start }
      return ($0.end ?? $0.start) < ($1.end ?? $1.start)
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(sorted)).flatMap { String(data: $0, encoding: .utf8) }
  }

  static func decode(_ json: String) -> [Self]? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    guard let values = try? decoder.decode([Self].self, from: Data(json.utf8)),
      values.allSatisfy({ $0.utcTiming != nil })
    else { return nil }
    return values
  }

  /// A validated UTC representation for the source timing type. The source
  /// zone stays on the timeline item as provenance; its projection uses the
  /// exact instants, retaining seconds and both readings of a repeated minute.
  var utcTiming: CalendarEventTiming? {
    guard (try? LorvexDate.parse(date).get()) != nil,
      start.timeIntervalSince1970.isFinite, let first = Self.fields(start)
    else { return nil }
    var last: (LorvexDate, TimeOfDay)?
    if let end {
      guard end.timeIntervalSince1970.isFinite, end >= start,
        let fields = Self.fields(end)
      else { return nil }
      last = fields
    }
    return try? CalendarEventTiming.fromFlatFields(
      startDate: first.0, startTime: first.1,
      endDate: last.flatMap { $0.0 == first.0 ? nil : $0.0 }, endTime: last?.1,
      allDay: false
    ).get()
  }

  private static func fields(_ instant: Date) -> (LorvexDate, TimeOfDay)? {
    let c = IsoDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
    guard let year = c.year, (1...9999).contains(year),
      let month = c.month, let day = c.day, let hour = c.hour, let minute = c.minute,
      let date = try? LorvexDate.parse(String(format: "%04d-%02d-%02d", year, month, day)).get(),
      let time = try? TimeOfDay.parse(String(format: "%02d:%02d", hour, minute)).get()
    else { return nil }
    return (date, time)
  }
}
