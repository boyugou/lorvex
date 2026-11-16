import Foundation
import LorvexCore
import MCP

/// Response-only temporal metadata accompanies the selected clock fields. It
/// never widens a date-only or title-only projection into timestamp disclosure.
enum CalendarEventTimeContext {
  static let readDescription =
    " Clock fields use each row's timezone. time_context identifies zoned/floating/all_day/date_only/unresolved values, their display/source/civil clock_basis, the source_timezone for recurrence, and known UTC start_at/end_at instants. Full rows or include=[time] expose canonical source_timing for edits. Source definitions omit unknown instants."

  static let writeDescription =
    " Timing patches use source civil coordinates. Use time_context.source_timing from full/time-detail reads to preserve an occurrence's frame. Whole-series edits use the stored master from search_calendar_events; a later occurrence's date is not the series anchor. For content-only edits, omit timing fields."

  static func timezone(for event: CalendarTimelineEvent) -> String? {
    guard !event.allDay, event.startTime != nil else { return nil }
    return event.projection?.timezone ?? sourceTimezone(for: event)
  }

  static func attach(
    to fields: inout [String: Value], event: CalendarTimelineEvent,
    options: CalendarEventValueOptions
  ) {
    let contextualFields: Set<String> = [
      "start_date", "start_time", "end_date", "end_time", "all_day", "timezone",
      "recurrence", "is_recurring",
    ]
    guard !contextualFields.isDisjoint(with: fields.keys) else { return }

    let kind = kind(of: event)
    let civil = ["all_day", "date_only", "floating"].contains(kind)
    var context: [String: Value] = [
      "kind": .string(kind),
      "clock_basis": .string(civil ? "civil" : event.projection == nil ? "source" : "display"),
    ]
    func put(_ key: String, _ value: String?) {
      if let value {
        context[key] = .string(value)
      } else if options.includeNulls {
        context[key] = .null
      }
    }
    put("source_timezone", sourceTimezone(for: event))

    // Any selected clock comes with its frame, even under fields=[start_time].
    // Floating/civil clocks explicitly have no timezone instead of inheriting
    // the server's device timezone.
    if fields["start_time"] != nil || fields["end_time"] != nil {
      fields["timezone"] = timezone(for: event).map(Value.string) ?? .null
    }
    if fields["start_time"] != nil {
      put("start_at", civil ? nil : event.projection.map { timestamp($0.start) })
    }
    if fields["end_time"] != nil {
      put("end_at", civil ? nil : event.projection?.end.map(timestamp))
    }

    // Canonical writes take source civil coordinates. Preserve them directly:
    // reverse-projecting a snapped 03:00 would lose an intended 02:30 rule.
    // Provider rows are read-only and use their exact instants for inspection.
    if event.editable, options.fields == nil,
      options.shape == .full || options.include.contains("time"),
      let source = sourceTiming(for: event)
    {
      var timing: [String: Value] = [
        "start_date": .string(source.startDate),
        "start_time": source.startTime.map(Value.string) ?? .null,
        "end_date": source.endDate.map(Value.string) ?? .null,
        "end_time": source.endTime.map(Value.string) ?? .null,
        "all_day": .bool(source.allDay),
        "timezone": source.timezone.map(Value.string) ?? .null,
      ]
      if !options.includeNulls { timing = timing.filter { $0.value != .null } }
      context["source_timing"] = .object(timing)
    }
    fields["time_context"] = .object(context)
  }

  private static func kind(of event: CalendarTimelineEvent) -> String {
    if event.allDay { return "all_day" }
    if event.startTime == nil { return "date_only" }
    if event.projection != nil { return "zoned" }
    guard let zone = sourceTimezone(for: event) else { return "floating" }
    return TimeZone(identifier: zone) == nil ? "unresolved" : "zoned"
  }

  private static func sourceTimezone(for event: CalendarTimelineEvent) -> String? {
    guard let zone = event.timezone, !zone.isEmpty else { return nil }
    return zone
  }

  private static func sourceTiming(for event: CalendarTimelineEvent) -> CalendarEventSourceTiming? {
    if let source = event.sourceTiming { return source }
    guard event.projection == nil else { return nil }
    return CalendarEventSourceTiming(
      startDate: event.startDate, startTime: event.startTime,
      endDate: event.endDate, endTime: event.endTime,
      allDay: event.allDay, timezone: event.timezone)
  }

  private static func timestamp(_ instant: Date) -> String {
    LorvexDateFormatters.iso8601Fractional.string(from: instant)
  }
}
