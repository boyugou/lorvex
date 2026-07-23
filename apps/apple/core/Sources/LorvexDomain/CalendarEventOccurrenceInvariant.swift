import Foundation

/// The LWW decision stored for one occurrence of a recurring calendar series.
public enum CalendarOccurrenceState: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
  case replacement
  case cancelled
  case inherit
}

/// Canonical structural invariant for every row in `calendar_events`.
public enum CalendarEventOccurrenceInvariant {
  public static func validate(
    eventId: String,
    recurrence: String?,
    seriesCutoverId: String? = nil,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: CalendarOccurrenceState?,
    recurrenceGeneration: String?,
    recurrenceTopologyVersion: String?
  ) -> Result<Void, ValidationError> {
    if let seriesCutoverId, seriesCutoverId != eventId {
      return .failure(.message("series_cutover_id must equal the base event id"))
    }
    if (seriesId == nil) != (recurrenceInstanceDate == nil) {
      return .failure(
        .message(
          "series_id and recurrence_instance_date must be set together "
            + "(both null for a base event, both non-null for an occurrence decision)"))
    }

    if let seriesId {
      if seriesId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .failure(.message("series_id must not be empty"))
      }
      if seriesId == eventId {
        return .failure(.message("an occurrence decision must not reference itself"))
      }
    }

    if let recurrenceInstanceDate,
      case .failure(let error) = ValidationFormat.validateDateFormat(recurrenceInstanceDate)
    {
      return .failure(
        .message("recurrence_instance_date failed validation: \(error.description)"))
    }

    if let recurrenceGeneration,
      case .failure(let error) = validateCanonicalHlc(
        recurrenceGeneration, field: "recurrence_generation")
    {
      return .failure(error)
    }
    if let recurrenceTopologyVersion,
      case .failure(let error) = validateCanonicalHlc(
        recurrenceTopologyVersion, field: "recurrence_topology_version")
    {
      return .failure(error)
    }

    if seriesId != nil {
      guard seriesCutoverId == nil else {
        return .failure(.message("an occurrence decision must not carry series_cutover_id"))
      }
      guard recurrence == nil else {
        return .failure(.message("an occurrence decision must not carry recurrence"))
      }
      guard occurrenceState != nil else {
        return .failure(.message("an occurrence decision requires occurrence_state"))
      }
      guard recurrenceGeneration != nil else {
        return .failure(.message("an occurrence decision requires recurrence_generation"))
      }
      guard recurrenceTopologyVersion == nil else {
        return .failure(
          .message("an occurrence decision must not carry recurrence_topology_version"))
      }
      return .success(())
    }

    guard occurrenceState == nil else {
      return .failure(.message("a base event must not carry occurrence_state"))
    }
    guard recurrenceTopologyVersion != nil else {
      return .failure(.message("a base event requires recurrence_topology_version"))
    }

    if recurrence != nil {
      guard recurrenceGeneration != nil else {
        return .failure(.message("a recurring master requires recurrence_generation"))
      }
    } else if recurrenceGeneration != nil {
      return .failure(.message("a plain event must not carry recurrence_generation"))
    }
    return .success(())
  }

  private static func validateCanonicalHlc(
    _ value: String, field: String
  ) -> Result<Void, ValidationError> {
    do {
      _ = try Hlc.parseCanonical(value)
      return .success(())
    } catch {
      return .failure(.message("\(field) must be a canonical HLC"))
    }
  }
}
