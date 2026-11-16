#if canImport(EventKit)
  @preconcurrency import EventKit
  import Foundation

  /// Exact source context that a display projection cannot reconstruct, notably
  /// recurring iPhone occurrences whose mirror rows deliberately have no rule.
  public enum EventKitComparison {
    public static func signature(for event: EKEvent) -> String? {
      let rules = (event.recurrenceRules ?? []).compactMap { rule -> String? in
        var fields: [String: Any] = [
          "frequency": rule.frequency.rawValue, "interval": rule.interval,
          "weekStart": rule.firstDayOfTheWeek,
          "weekdays": (rule.daysOfTheWeek ?? []).map {
            "\($0.weekNumber):\($0.dayOfTheWeek.rawValue)"
          }.sorted(),
        ]
        for (key, numbers) in [
          ("monthDays", rule.daysOfTheMonth), ("yearDays", rule.daysOfTheYear),
          ("months", rule.monthsOfTheYear), ("weeks", rule.weeksOfTheYear),
          ("positions", rule.setPositions),
        ] {
          fields[key] = (numbers ?? []).map(\.intValue).sorted()
        }
        if let end = rule.recurrenceEnd {
          fields["count"] = end.occurrenceCount
          fields["until"] = end.endDate?.timeIntervalSince1970
        }
        return encode(fields)
      }.sorted()
      let alarms = (event.alarms ?? []).compactMap { alarm -> String? in
        var fields: [String: Any] = [
          "offset": alarm.relativeOffset, "proximity": alarm.proximity.rawValue,
        ]
        fields["absolute"] = alarm.absoluteDate?.timeIntervalSince1970
        fields["place"] = alarm.structuredLocation?.title
        if let location = alarm.structuredLocation {
          fields["latitude"] = location.geoLocation?.coordinate.latitude
          fields["longitude"] = location.geoLocation?.coordinate.longitude
          fields["radius"] = location.radius
        }
        return encode(fields)
      }.sorted()
      let participants = (event.attendees ?? []).compactMap(participant).sorted()
      guard rules.count == (event.recurrenceRules ?? []).count,
        alarms.count == (event.alarms ?? []).count,
        participants.count == (event.attendees ?? []).count
      else { return nil }
      return encode([
        "rules": rules, "alarms": alarms, "status": event.status.rawValue,
        "availability": event.availability.rawValue, "detached": event.isDetached,
        "participants": participants, "organizer": event.organizer.flatMap(participant) ?? "",
      ])
    }

    private static func participant(_ participant: EKParticipant) -> String? {
      encode([
        "name": participant.name ?? "", "address": participant.url.absoluteString,
        "role": participant.participantRole.rawValue, "type": participant.participantType.rawValue,
        "status": participant.participantStatus.rawValue,
      ])
    }

    private static func encode(_ object: [String: Any]) -> String? {
      (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) }
    }
  }
#endif
