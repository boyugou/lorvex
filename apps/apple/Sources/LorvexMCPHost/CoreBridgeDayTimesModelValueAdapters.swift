import Foundation
import LorvexCore
import LorvexDomain
import MCP

/// Maps the `LorvexCore` day-times models onto the MCP `Value` JSON shapes the
/// day-times tools return. Times are `HH:MM`, with `24:00` for the midnight
/// that ends the day; tasks use the compact task shape.
extension CoreBridgeClient {
  static func dayTimesProposalValue(from proposal: DayTimesProposal) -> Value {
    .object([
      "date": .string(proposal.date),
      "working_hours": .object([
        "start": .string(TimeOfDay.rangeBoundString(proposal.workingHours.lowerBound)),
        "end": .string(TimeOfDay.rangeBoundString(proposal.workingHours.upperBound)),
      ]),
      "available_minutes": .int(proposal.availableMinutes),
      "placements": .array(
        proposal.placements.map { placement in
          .object([
            "task": taskValue(from: placement.task, options: .compact),
            "start_time": .string(TimeOfDay.rangeBoundString(placement.time.lowerBound)),
            "end_time": .string(TimeOfDay.rangeBoundString(placement.time.upperBound)),
          ])
        }),
      "events": .array(proposal.events.map(dayTimesEventValue(from:))),
      "unscheduled": taskValues(from: proposal.unscheduled, options: .compact),
    ])
  }

  /// A calendar event the suggestion worked around. `title` is null for a
  /// device calendar event when the calendar setting shares only busy time,
  /// and `event_id` is null for every device calendar event.
  static func dayTimesEventValue(from event: DayTimesProposal.Event) -> Value {
    .object([
      "start_time": .string(TimeOfDay.rangeBoundString(event.time.lowerBound)),
      "end_time": .string(TimeOfDay.rangeBoundString(event.time.upperBound)),
      "title": event.title.map(Value.string) ?? .null,
      "event_id": event.eventID.map(Value.string) ?? .null,
      "source": .string(event.source.rawValue),
    ])
  }
}
