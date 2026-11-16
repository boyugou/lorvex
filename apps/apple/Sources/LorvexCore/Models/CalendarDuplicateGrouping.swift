import Foundation

public enum CalendarDuplicateGrouping: String, CaseIterable, Sendable {
  case off
  case strict
  case titleAndTime

  public static let preferenceKey = "calendarDuplicateGrouping"

  public static func remembered(in defaults: UserDefaults) -> Self {
    defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .strict
  }

  /// Groups fully readable imported copies from distinct known calendars.
  /// Same-calendar ambiguity leaves the entire matching set visible.
  public func events(_ input: [CalendarTimelineEvent]) -> [CalendarTimelineEvent] {
    let events = input.flatMap(\.displayCopies)
    guard self != .off else { return events }
    var matches: [MatchKey: [Int]] = [:]
    for (index, event) in events.enumerated() {
      if let key = matchKey(event) { matches[key, default: []].append(index) }
    }
    var replacements: [Int: CalendarTimelineEvent] = [:]
    var hidden = Set<Int>()
    for indices in matches.values where indices.count > 1 {
      let copies = indices.map { events[$0] }
      guard Set(copies.compactMap { $0.origin?.calendarID }).count == copies.count,
        let firstIndex = indices.first
      else { continue }
      let sorted = copies.sorted {
        ($0.origin?.calendarID ?? "", $0.eventID, $0.id)
          < ($1.origin?.calendarID ?? "", $1.eventID, $1.id)
      }
      var representative = sorted[0]
      representative.combinedEventCopies = Array(sorted.dropFirst())
      replacements[firstIndex] = representative
      hidden.formUnion(indices.dropFirst())
    }
    return events.enumerated().compactMap { index, event in
      hidden.contains(index) ? nil : replacements[index] ?? event
    }
  }

  private func matchKey(_ event: CalendarTimelineEvent) -> MatchKey? {
    guard event.source == "provider", !event.editable, event.eventType == "event",
      let origin = event.origin, !origin.calendarID.isEmpty,
      !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let timing = Timing(event)
    else { return nil }
    return MatchKey(
      title: event.title, timing: timing,
      details: self == .strict ? Details(event) : nil)
  }

  private struct MatchKey: Hashable {
    let title: String
    let timing: Timing
    let details: Details?
  }

  private enum Timing: Hashable {
    case allDay(String, String)
    case floating(String, String, String, String)
    case fixed(Date, Date)

    init?(_ event: CalendarTimelineEvent) {
      if event.allDay {
        self = .allDay(event.startDate, event.endDate ?? event.startDate)
      } else if let projection = event.projection, let end = projection.end,
        end > projection.start, event.timezone != nil
      {
        self = .fixed(projection.start, end)
      } else if event.timezone == nil, let start = event.startTime, let end = event.endTime {
        self = .floating(event.startDate, start, event.endDate ?? event.startDate, end)
      } else {
        return nil
      }
    }
  }

  private struct Details: Hashable {
    let location: String?
    let notes: String?
    let url: String?
    let organizer: String?
    let attendees: [CalendarEventAttendee]
    let timezone: String?
    let isRecurring: Bool
    let recurrenceRule: String?
    let recurrenceSummary: String?
    let contentSignature: String?

    init(_ event: CalendarTimelineEvent) {
      location = event.location
      notes = event.notes
      url = event.url
      organizer = event.personName
      attendees = (event.attendees ?? []).sorted {
        ($0.email, $0.name ?? "", $0.status ?? "") < ($1.email, $1.name ?? "", $1.status ?? "")
      }
      timezone = event.timezone
      isRecurring = event.isRecurring
      recurrenceRule = event.recurrenceRule
      recurrenceSummary = event.recurrenceSummary
      contentSignature = event.origin?.contentSignature
    }
  }
}

extension CalendarTimelineEvent {
  public func containsDisplayCopy(id: String?) -> Bool {
    guard let id else { return false }
    return self.id == id || combinedEventCopies.contains { $0.containsDisplayCopy(id: id) }
  }

  public var displayCopies: [CalendarTimelineEvent] {
    var first = self
    first.combinedEventCopies = []
    return [first] + combinedEventCopies.flatMap(\.displayCopies)
  }
}

extension CalendarTimelineSnapshot {
  public func groupingDuplicates(_ mode: CalendarDuplicateGrouping) -> Self {
    var snapshot = self
    snapshot.events = mode.events(events)
    return snapshot
  }
}
