/// Helpers for calendar consumers that persist identity beyond one timeline
/// render, such as App Entities and Core Spotlight.
extension CalendarTimelineEvent {
  /// Collapses expanded occurrences to one representative per stable source
  /// event or recurring-series segment.
  ///
  /// ``id`` is intentionally occurrence-specific and may change when a series'
  /// recurrence generation changes. Persistent integrations must key by
  /// ``eventID`` instead. When a visible replacement and a natural occurrence
  /// share that stable address, prefer the natural occurrence so the
  /// representative describes the series rather than one overridden slot.
  public static func stableSourceRepresentatives(
    in events: [CalendarTimelineEvent]
  ) -> [CalendarTimelineEvent] {
    var representatives: [CalendarTimelineEvent] = []
    var indexByEventID: [CalendarTimelineEvent.ID: Int] = [:]
    representatives.reserveCapacity(events.count)

    for event in events {
      if let index = indexByEventID[event.eventID] {
        if representatives[index].occurrenceState != nil, event.occurrenceState == nil {
          representatives[index] = event
        }
        continue
      }
      indexByEventID[event.eventID] = representatives.count
      representatives.append(event)
    }
    return representatives
  }
}
