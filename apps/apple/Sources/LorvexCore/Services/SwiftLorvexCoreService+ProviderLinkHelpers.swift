import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  static func providerLinkFields(
    providerSource: String,
    providerEventID: String
  ) throws -> ProviderLinkFields {
    let providerKind = providerSource.trimmingCharacters(in: .whitespacesAndNewlines)
    // Callers (the assistant) pass the composite id the timeline / search
    // surface ("kind:scope:key"). Decompose it so the stored row's bare
    // provider_event_key + scope match what the reads (which split the same
    // composite) and the JOIN to provider_calendar_events look up. A plain
    // bare key — e.g. the EventKit write-back path — has no ":" triple and
    // falls through to the bare-key form below.
    if let composite = try providerEventLookupFields(providerEventID: providerEventID),
      composite.providerKind == providerKind
    {
      return composite
    }
    let providerScope = providerKind == ProviderKind.eventkit ? Self.eventKitScope : ""
    switch ProviderLink.normalizeFields(
      providerKind: providerKind,
      providerScope: providerScope,
      providerEventKey: providerEventID
    ) {
    case .success(let fields):
      return fields
    case .failure(let error):
      throw LorvexCoreError.unsupportedOperation(error.description)
    }
  }

  static func providerEventLookupFields(providerEventID: String) throws -> ProviderLinkFields? {
    let parts = providerEventID.split(
      separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    switch ProviderLink.normalizeFields(
      providerKind: String(parts[0]),
      providerScope: String(parts[1]),
      providerEventKey: String(parts[2])
    ) {
    case .success(let fields):
      return fields
    case .failure(let error):
      throw LorvexCoreError.unsupportedOperation(error.description)
    }
  }

  static func calendarEventLink(from link: TaskProviderEventLink) -> TaskCalendarEventLink {
    TaskCalendarEventLink(
      taskID: link.taskId,
      eventID: link.providerEventKey,
      providerEventID: link.providerEventKey,
      providerSource: link.providerKind
    )
  }
}
