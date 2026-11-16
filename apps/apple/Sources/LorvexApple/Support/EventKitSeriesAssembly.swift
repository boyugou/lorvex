import Foundation
import LorvexStore

/// One enumerated EventKit occurrence, mapped at its REAL start/end, plus the
/// series facts the assembler needs: whether the occurrence was detached
/// (modified away from the series) and the original projected slot it was
/// detached from.
struct EventKitOccurrence: Equatable {
  var event: EventKitFetchedEvent
  var isDetached: Bool
  /// YMD of the slot the series rule projected this occurrence at (EventKit's
  /// `occurrenceDate`). Differs from `event.startDate` when the user moved it.
  var occurrenceYmd: String?
}

/// Collapses EventKit's one-EKEvent-per-occurrence enumeration into provider
/// event rows that render moved and cancelled occurrences correctly.
///
/// `EKEventStore.events(matching:)` yields every occurrence of a recurring
/// series, all sharing one stable key. Keeping only the first occurrence and
/// projecting the raw rule renders the ORIGINAL projection: a moved occurrence
/// shows at its old slot and a cancelled one still shows. Instead, each series
/// becomes:
///
/// - one master row carrying the rule plus `recurrenceExceptions` for every
///   projected date with no surviving on-rule occurrence (covering both
///   cancelled occurrences and the original slots of moved ones), and
/// - one standalone, non-recurring row per detached (moved/edited) occurrence
///   at its real time, keyed `"{seriesKey}:{originalYmd}"` so the row is stable
///   across fetches.
///
/// Exceptions are derived by diffing the rule's projection against the
/// enumerated on-rule occurrences inside the fetched window — EventKit exposes
/// no EXDATE list, but its enumeration is authoritative within the window.
/// Row count stays bounded: one master per series plus one row per detached
/// occurrence, never one row per projected occurrence.
///
/// The master starts where the series does (`seriesStarts`, the series' first
/// occurrence as EventKit reports it), not at its first occurrence in the
/// window, retaining the source anchor for rule metadata and legacy COUNT
/// projection. Zoned timed observations carry their exact occurrence set too;
/// those instants drive projection, with other cached weeks merged at ingest.
/// Without a known start, the first occurrence in the window stands in.
enum EventKitSeriesAssembly {
  /// Hard cap on projected dates examined per series. Daily over the widest
  /// ~7-year ingest window is ~2.6k; the cap only stops a pathological rule.
  static let maxProjectedOccurrences = 4000

  static func assemble(
    _ occurrences: [EventKitOccurrence],
    seriesStarts: [String: EventKitFetchedEvent] = [:],
    windowEndYmd: String
  ) -> [EventKitFetchedEvent] {
    var order: [String] = []
    var groups: [String: [EventKitOccurrence]] = [:]
    for occurrence in occurrences {
      let key = occurrence.event.key
      if groups[key] == nil { order.append(key) }
      groups[key, default: []].append(occurrence)
    }

    var results: [EventKitFetchedEvent] = []
    for key in order {
      guard let group = groups[key] else { continue }
      results.append(
        contentsOf: assembleSeries(
          group, seriesStart: seriesStarts[key], windowEndYmd: windowEndYmd))
    }
    return results
  }

  private static func assembleSeries(
    _ group: [EventKitOccurrence], seriesStart: EventKitFetchedEvent?, windowEndYmd: String
  ) -> [EventKitFetchedEvent] {
    guard let inWindowRule = group.compactMap({ $0.event.recurrence }).first else {
      // Non-recurring, or a rule the bridge could not express: a single
      // representative row (the first enumerated occurrence).
      return group.first.map { [$0.event] } ?? []
    }

    let firstInWindow = group.first { !$0.isDetached } ?? group[0]
    let master: EventKitFetchedEvent
    let rule: String
    if let seriesStart, let startRule = seriesStart.recurrence,
      seriesStart.startDate <= firstInWindow.event.startDate
    {
      master = seriesStart
      rule = startRule
    } else {
      master = firstInWindow.event
      rule = inWindowRule
    }
    let onRuleDates = Set(group.filter { !$0.isDetached }.map(\.event.startDate))
    // Cancellations are known only where the window was fetched: from its
    // first occurrence (an on-rule one, or a moved one's original slot) on.
    // Earlier projected dates were not enumerated, so none is called cancelled.
    let windowSlots =
      group.filter { !$0.isDetached }.map(\.event.startDate)
      + group.filter(\.isDetached).map { $0.occurrenceYmd ?? $0.event.startDate }
    let exceptions = projectedExceptions(
      rule: rule, baseYmd: master.startDate,
      fromYmd: max(master.startDate, windowSlots.min() ?? master.startDate),
      windowEndYmd: windowEndYmd, onRuleDates: onRuleDates)

    let precise =
      group.allSatisfy { $0.event.occurrenceInstants != nil }
      ? group.filter { !$0.isDetached }.flatMap { $0.event.occurrenceInstants ?? [] } : nil
    var results = [
      rebuilt(
        master, key: master.key, recurrence: rule,
        recurrenceExceptions: encodeExceptions(exceptions), occurrenceInstants: precise)
    ]
    // Each moved/edited occurrence renders standalone at its real time; its
    // original slot is already excluded from the master's projection above.
    for occurrence in group where occurrence.isDetached {
      let originalYmd = occurrence.occurrenceYmd ?? occurrence.event.startDate
      results.append(
        rebuilt(
          occurrence.event, key: "\(occurrence.event.key):\(originalYmd)",
          recurrence: nil, recurrenceExceptions: nil))
    }
    return results
  }

  /// Dates the rule projects from `baseYmd` that fall within `[fromYmd,
  /// windowEndYmd]` and have no surviving on-rule occurrence — i.e. cancelled
  /// occurrences and the original slots of moved ones. A rule the projection
  /// engine cannot parse yields no exceptions (the master renders the raw
  /// projection, the pre-assembly behavior).
  private static func projectedExceptions(
    rule: String, baseYmd: String, fromYmd: String, windowEndYmd: String,
    onRuleDates: Set<String>
  ) -> [String] {
    var exceptions: [String] = []
    guard
      var date = try? CalendarRecurrence.firstOccurrenceOnOrAfter(
        recurrenceJson: rule, baseDateYmd: baseYmd, targetDateYmd: fromYmd)
    else { return [] }
    // The projection stops at an UNTIL date but not after a COUNT of
    // occurrences, so the series' last date bounds the walk too.
    let lastDate =
      (try? CalendarRecurrence.countEndDate(recurrenceJson: rule, baseDate: baseYmd))
      .flatMap { $0 }.map { min($0, windowEndYmd) } ?? windowEndYmd
    var iterations = 0
    while date <= lastDate, iterations < maxProjectedOccurrences {
      if !onRuleDates.contains(date) { exceptions.append(date) }
      iterations += 1
      guard
        let next = try? CalendarRecurrence.nextOccurrenceStrictlyAfter(
          recurrenceJson: rule, baseDateYmd: baseYmd, todayYmd: date)
      else { break }
      date = next
    }
    return exceptions
  }

  /// Wire form: a JSON array of `YYYY-MM-DD` strings; `nil` when empty.
  private static func encodeExceptions(_ dates: [String]) -> String? {
    guard !dates.isEmpty else { return nil }
    return "[" + dates.map { "\"\($0)\"" }.joined(separator: ",") + "]"
  }

  private static func rebuilt(
    _ event: EventKitFetchedEvent, key: String, recurrence: String?,
    recurrenceExceptions: String?, occurrenceInstants: [ProviderOccurrenceInstant]? = nil
  ) -> EventKitFetchedEvent {
    EventKitFetchedEvent(
      key: key, title: event.title, notes: event.notes,
      startDate: event.startDate, startTime: event.startTime,
      endDate: event.endDate, endTime: event.endTime,
      allDay: event.allDay, location: event.location, timezone: event.timezone,
      recurrence: recurrence, recurrenceExceptions: recurrenceExceptions,
      color: event.color, organizerEmail: event.organizerEmail,
      url: event.url, attendees: event.attendees,
      occurrenceInstants: recurrence != nil ? occurrenceInstants : event.occurrenceInstants,
      origin: event.origin,
      legacyKey: event.legacyKey.map { $0 + String(key.dropFirst(event.key.count)) })
  }
}
