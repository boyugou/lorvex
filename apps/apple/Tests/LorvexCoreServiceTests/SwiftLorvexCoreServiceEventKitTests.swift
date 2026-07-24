import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Coverage for the EventKit provider-mirror facade
/// (`EventKitProviderServicing`) on `SwiftLorvexCoreService`: ingest upserts
/// into `provider_calendar_events` and the events surface through the timeline
/// union (which is how they reach the week grid), tier redaction is enforced at
/// ingest, write-back records a `task_provider_event_links` row, and the scope
/// toggle / clear behave.
final class SwiftLorvexCoreServiceEventKitTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func fetched() -> [EventKitFetchedEvent] {
    [
      EventKitFetchedEvent(
        key: "ek-1", title: "Dentist", notes: "bring x-rays",
        startDate: "2026-06-02", startTime: "10:00", endDate: "2026-06-02", endTime: "10:30",
        allDay: false, location: "123 Main St", timezone: "America/Los_Angeles")
    ]
  }

  /// Persist the owner-device `full_details` tier explicitly. The timeline read
  /// honors the effective calendar AI-access tier (defense in depth behind
  /// ingest-time redaction), so round-trip tests that assert on real provider
  /// detail pin the tier rather than inheriting whatever the domain default
  /// happens to be — the assertions then describe the tier under test, not the
  /// default's current value.
  private func optIntoFullDetailTier(_ service: SwiftLorvexCoreService) async throws {
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
  }

  private func saveProviderFocusSchedule(
    _ service: SwiftLorvexCoreService, date: String, includeFreeform: Bool = false
  ) async throws {
    var blocks = [
      FocusScheduleBlock(
        blockType: "event", startTime: "09:00", endTime: "10:00",
        eventSource: .provider, title: "Private appointment")
    ]
    if includeFreeform {
      blocks.append(
        FocusScheduleBlock(
          blockType: "event", startTime: "10:00", endTime: "10:30",
          eventSource: .freeform, title: "Authored hold"))
    }
    _ = try await service.saveFocusSchedule(date: date, blocks: blocks, rationale: nil)
  }

  private func focusScheduleSyncState(
    _ service: SwiftLorvexCoreService, date: String
  ) throws -> (version: String, payload: String?) {
    try service.read { db in
      let version = try String.fetchOne(
        db, sql: "SELECT version FROM focus_schedule WHERE date = ?", arguments: [date]) ?? ""
      let payload = try String.fetchOne(
        db,
        sql: """
          SELECT payload FROM sync_outbox
          WHERE entity_type = 'focus_schedule' AND entity_id = ? AND synced_at IS NULL
          ORDER BY id DESC LIMIT 1
          """,
        arguments: [date])
      return (version, payload)
    }
  }

  /// Whether the EventKit scope is enabled AND has refreshed at least once —
  /// exactly the predicate the timeline / linked-events reads use to surface
  /// provider rows. FIX-2 abort must leave this `false` (the downgrade disabled
  /// the scope and the aborted ingest must not flip it back to refreshSuccess).
  private func eventKitScopeSurfaces(_ service: SwiftLorvexCoreService) throws -> Bool {
    try service.read { db in
      try Bool.fetchOne(
        db,
        sql: """
          SELECT EXISTS(
            SELECT 1 FROM provider_scope_runtime_state
            WHERE provider_kind = 'eventkit' AND provider_scope = 'device'
              AND availability_state = ? AND last_refresh_success_at IS NOT NULL)
          """,
        arguments: [AvailabilityState.enabled]) ?? false
    }
  }

  // MARK: - Ingest reaches the timeline union

  func testFullDetailsIngestSurfacesVerbatimInTimeline() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    let rows = EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails)
    let count = try service.ingestEventKitEvents(
      rows, builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    XCTAssertEqual(count, 1)

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let event = try XCTUnwrap(snapshot.events.first { $0.source == "provider" })
    XCTAssertEqual(event.title, "Dentist")
    XCTAssertEqual(event.location, "123 Main St")
  }

  func testBusyOnlyIngestRedactsBeforeMirroring() async throws {
    let service = try makeService()
    let rows = EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .busyOnly)
    _ = try service.ingestEventKitEvents(
      rows, builtAtMode: .busyOnly, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let event = try XCTUnwrap(snapshot.events.first { $0.source == "provider" })
    // Redaction happened at INGEST: the mirror row itself carries no title/location.
    XCTAssertEqual(event.title, "Busy")
    XCTAssertNil(event.location)
  }

  func testOffTierIngestsNothing() async throws {
    let service = try makeService()
    let rows = EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .off)
    XCTAssertEqual(
      try service.ingestEventKitEvents(
        rows, builtAtMode: .off, windowStart: "2026-06-01", windowEnd: "2026-06-05"), 0)

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertFalse(snapshot.events.contains { $0.source == "provider" })
  }

  // MARK: - Titleless events do not abort the refresh

  /// A system calendar event with no title reaches the schema's NOT NULL
  /// `title` column. Ingest coalesces it to "(untitled)" so one untitled event
  /// can't abort the single-transaction batch and drop every other event's
  /// mirror row in the same refresh.
  func testTitlelessEventCoalescesAndDoesNotAbortBatch() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    let batch = [
      EventKitFetchedEvent(
        key: "ek-untitled", title: nil, notes: nil,
        startDate: "2026-06-03", startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
        allDay: false, location: nil, timezone: "America/Los_Angeles"),
      EventKitFetchedEvent(
        key: "ek-titled", title: "Standup", notes: nil,
        startDate: "2026-06-03", startTime: "10:00", endDate: "2026-06-03", endTime: "10:30",
        allDay: false, location: nil, timezone: "America/Los_Angeles"),
    ]
    let rows = EventKitIngest.providerRows(from: batch, scope: "device", accessMode: .fullDetails)
    let count = try service.ingestEventKitEvents(
      rows, builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    XCTAssertEqual(count, 2)

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let providerTitles = snapshot.events.filter { $0.source == "provider" }.map(\.title).sorted()
    XCTAssertEqual(providerTitles, ["(untitled)", "Standup"])
  }

  // MARK: - Attendees round-trip through the read path

  private func attendeeFetched() -> [EventKitFetchedEvent] {
    [
      EventKitFetchedEvent(
        key: "ek-att", title: "Design sync", notes: nil,
        startDate: "2026-06-04", startTime: "11:00", endDate: "2026-06-04", endTime: "12:00",
        allDay: false, location: nil, timezone: "America/Los_Angeles",
        organizerEmail: "alice@example.com",
        attendees: [
          EventKitFetchedAttendee(email: "alice@example.com", name: "Alice", status: .accepted),
          EventKitFetchedAttendee(email: "bob@example.com", status: .needsAction),
        ]),
    ]
  }

  func testFullDetailsIngestSurfacesAttendeesInTimeline() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    let rows = EventKitIngest.providerRows(
      from: attendeeFetched(), scope: "device", accessMode: .fullDetails)
    _ = try service.ingestEventKitEvents(
      rows, builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let event = try XCTUnwrap(
      snapshot.events.first { $0.source == "provider" && $0.title == "Design sync" })
    let attendees = try XCTUnwrap(event.attendees)
    XCTAssertEqual(attendees.map(\.email).sorted(), ["alice@example.com", "bob@example.com"])
    let alice = try XCTUnwrap(attendees.first { $0.email == "alice@example.com" })
    XCTAssertEqual(alice.name, "Alice")
    XCTAssertEqual(alice.status, "accepted")
    let bob = try XCTUnwrap(attendees.first { $0.email == "bob@example.com" })
    XCTAssertEqual(bob.status, "needs-action")
  }

  /// Full-detail ingest surfaces the provider `description` (as `notes`),
  /// `organizer_email` (as `person_name`), and `video_call_url` (as `url`)
  /// through the timeline read — previously these columns were written but never
  /// projected on the read path.
  func testFullDetailsIngestSurfacesDescriptionOrganizerAndVideoURL() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    let event = EventKitFetchedEvent(
      key: "ek-detail", title: "Design sync", notes: "confidential agenda",
      startDate: "2026-06-04", startTime: "11:00", endDate: "2026-06-04", endTime: "12:00",
      allDay: false, location: "HQ", timezone: "America/Los_Angeles",
      organizerEmail: "alice@example.com",
      url: "https://meet.example.com/xyz")
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let item = try XCTUnwrap(snapshot.events.first { $0.source == "provider" })
    XCTAssertEqual(item.notes, "confidential agenda")
    XCTAssertEqual(item.personName, "alice@example.com")
    XCTAssertEqual(item.url, "https://meet.example.com/xyz")
  }

  func testBusyOnlyIngestDropsAttendees() async throws {
    let service = try makeService()
    let rows = EventKitIngest.providerRows(
      from: attendeeFetched(), scope: "device", accessMode: .busyOnly)
    _ = try service.ingestEventKitEvents(
      rows, builtAtMode: .busyOnly, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let event = try XCTUnwrap(snapshot.events.first { $0.source == "provider" })
    XCTAssertNil(event.attendees)
  }

  // MARK: - Stale reconciliation

  func testIngestDropsRowsAbsentFromLatestFetchInWindow() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    // Re-ingest an empty batch over the same window: the in-window "ek-1" is
    // reconciled away.
    _ = try service.ingestEventKitEvents(
      [], builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertFalse(snapshot.events.contains { $0.source == "provider" })
  }

  func testIngestPreservesRowsOutsideTheIngestedWindow() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    // Mirror an event on 2026-06-02.
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    // Ingest a DIFFERENT, non-overlapping window with an empty batch. The
    // June 2 row must survive — reconciliation is window-local.
    _ = try service.ingestEventKitEvents(
      [], builtAtMode: .fullDetails, windowStart: "2026-07-01", windowEnd: "2026-07-05")

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertTrue(snapshot.events.contains { $0.source == "provider" && $0.title == "Dentist" })
  }

  // MARK: - Write-back link row

  func testWriteBackLinkRecordsAndUnrecordsLink() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Scheduled", notes: "")

    let link = try service.linkTaskToEventKitEvent(taskID: task.id, providerEventKey: "ek-wb-1")
    XCTAssertEqual(link.providerKind, "eventkit")
    XCTAssertEqual(link.providerEventKey, "ek-wb-1")

    let links = try service.eventKitLinksForTask(taskID: task.id)
    XCTAssertEqual(links.map(\.providerEventKey), ["ek-wb-1"])

    let result = try service.unlinkTaskFromEventKitEvent(taskID: task.id, providerEventKey: "ek-wb-1")
    XCTAssertTrue(result.deleted)
    XCTAssertTrue(try service.eventKitLinksForTask(taskID: task.id).isEmpty)
  }

  func testWriteBackDirectLinkRecordsMcpIdempotencyMarker() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Scheduled", notes: "")
    let context = McpIdempotencyContext(
      toolName: "link_task_to_provider_event",
      key: "eventkit-link-key",
      checksum: "eventkit-link-checksum")

    _ = try SwiftLorvexCoreService.$currentMCPIdempotency.withValue(context) {
      try service.linkTaskToEventKitEvent(taskID: task.id, providerEventKey: "ek-wb-2")
    }

    let outcome = try await service.lookupMcpIdempotency(
      toolName: context.toolName,
      key: context.key,
      checksum: context.checksum)

    guard case .hit(let payload) = outcome else {
      return XCTFail("Expected durable applied marker, got \(outcome)")
    }
    XCTAssertTrue(McpIdempotencyDurablePayload.isAppliedWithoutResponse(payload))
  }

  func testCoreCalendarProviderLinkSurfaceReturnsLinkedEventsTasksAndAuditRows() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    let task = try await service.createTask(title: "Prepare for dentist", notes: "")

    // link/unlink_task_to_provider_event are MCP tools; the diagnostics
    // changelog these audit-row assertions read is an assistant-facing surface
    // (`user` rows are filtered out), so drive the writes under the assistant
    // binding the MCP host applies.
    let link = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.linkTaskToProviderEvent(
        taskID: task.id,
        providerEventID: "ek-1",
        providerSource: "eventkit")
    }

    XCTAssertEqual(link.taskID, task.id)
    XCTAssertEqual(link.providerEventID, "ek-1")
    XCTAssertEqual(link.providerSource, "eventkit")

    let events = try await service.getLinkedEventsForTask(taskID: task.id)
    let event = try XCTUnwrap(events.first)
    XCTAssertEqual(event.id, "eventkit:device:ek-1")
    XCTAssertEqual(event.title, "Dentist")
    XCTAssertFalse(event.editable)
    XCTAssertEqual(event.eventType, "event")
    XCTAssertEqual(event.timezone, "America/Los_Angeles")

    let tasksByCompositeID = try await service.getLinkedTasksForEvent(
      eventID: "eventkit:device:ek-1")
    let tasksByProviderKey = try await service.getLinkedTasksForEvent(eventID: "ek-1")
    XCTAssertEqual(tasksByCompositeID.map(\.id), [task.id])
    XCTAssertEqual(tasksByProviderKey.map(\.id), [task.id])

    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.unlinkTaskFromProviderEvent(taskID: task.id, providerEventID: "ek-1")
    }
    let eventsAfterUnlink = try await service.getLinkedEventsForTask(taskID: task.id)
    let tasksAfterUnlink = try await service.getLinkedTasksForEvent(eventID: "ek-1")
    XCTAssertTrue(eventsAfterUnlink.isEmpty)
    XCTAssertTrue(tasksAfterUnlink.isEmpty)

    let changelog = try await service.loadRuntimeDiagnostics().changelog.entries
    XCTAssertTrue(changelog.contains {
      $0.entityType == "task" && $0.operation == "upsert"
        && $0.summary.contains("device-local calendar link")
    })
    XCTAssertTrue(changelog.contains {
      $0.entityType == "task" && $0.operation == "delete"
        && $0.summary.contains("device-local calendar link")
    })
    let leakedProviderDetailCount = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM ai_changelog
          WHERE entity_id = ?
            AND summary LIKE '%device-local calendar link%'
            AND (
              summary LIKE '%ek-1%'
              OR summary LIKE '%eventkit%'
              OR before_json IS NOT NULL
              OR after_json IS NOT NULL
            )
          """,
        arguments: [task.id]) ?? -1
    }
    XCTAssertEqual(
      leakedProviderDetailCount, 0,
      "synced audit rows must not carry identifiers or snapshots from device-local providers")
  }

  // MARK: - Provider-mirror search + composite-id link round-trip

  /// search_calendar_events must include provider/EventKit-mirror events, not
  /// only canonical Lorvex-owned events. Regression for the mirror being
  /// invisible to search while present in the timeline.
  func testSearchCalendarEventsIncludesProviderMirror() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    let results = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertTrue(
      results.contains { $0.source == "provider" && $0.title == "Dentist" },
      "provider-mirror events must be searchable")

    // Case-insensitive, and date-bounded search both still reach the mirror.
    let lowercased = try await service.searchCalendarEvents(
      query: "dentist", from: "2026-06-01", to: "2026-06-05", limit: 50)
    XCTAssertTrue(lowercased.contains { $0.id == "eventkit:device:ek-1" })
  }

  /// FIX 1 (search leak): `searchCalendarEvents` must not surface provider
  /// (EventKit) detail below the full-detail tier. Even with a full-detail row
  /// still at rest, a `busy_only` search returns no provider hit — the LIKE scan
  /// over real titles/locations is both meaningless (every hit would redact to
  /// "Busy") and a match/no-match oracle over detail the tier forbids, so the
  /// provider merge is skipped entirely. The tier is flipped WITHOUT the
  /// downgrade purge (a direct `device_state` write) so a full-detail row
  /// genuinely survives at rest for the search to (not) leak.
  func testSearchOmitsProviderDetailUnderBusyTier() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    // Full detail is searchable under the pinned full tier.
    let fullHits = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertTrue(fullHits.contains { $0.source == "provider" && $0.title == "Dentist" })

    // Flip the effective tier to busy_only WITHOUT purging, leaving the
    // full-detail row at rest.
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .busyOnly)
    }

    let busyHits = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertFalse(
      busyHits.contains { $0.source == "provider" },
      "search must not surface provider detail under busy_only, even for a row at rest")
    // The location text is likewise unreachable through search.
    let locationHits = try await service.searchCalendarEvents(
      query: "Main St", from: nil, to: nil, limit: nil)
    XCTAssertFalse(locationHits.contains { $0.source == "provider" })
  }

  /// Linking with the composite id the timeline/search surface
  /// (`kind:scope:key`) must round-trip through both read directions.
  /// Regression for the write storing the whole composite as the bare key,
  /// which made both reads return nothing.
  func testProviderLinkRoundTripsUsingTimelineCompositeID() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    let task = try await service.createTask(title: "Prep for dentist", notes: "")

    _ = try await service.linkTaskToProviderEvent(
      taskID: task.id,
      providerEventID: "eventkit:device:ek-1",
      providerSource: "eventkit")

    let events = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertEqual(events.map(\.id), ["eventkit:device:ek-1"])
    let linkedTasks = try await service.getLinkedTasksForEvent(eventID: "eventkit:device:ek-1")
    XCTAssertEqual(linkedTasks.map(\.id), [task.id])
  }

  /// FIX 3 (linked-events leak): `getLinkedEventsForTask` honors the effective
  /// calendar AI-access tier. Under `busy_only`, a linked provider event's
  /// detail (title, location) is redacted to bare occupancy; under `off` the
  /// link surfaces no provider event at all. The tier is flipped WITHOUT the
  /// downgrade purge so a full-detail row survives at rest for the read to
  /// redact.
  func testLinkedEventsRedactProviderDetailUnderReducedTiers() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    let task = try await service.createTask(title: "Prep for dentist", notes: "")
    _ = try await service.linkTaskToProviderEvent(
      taskID: task.id, providerEventID: "ek-1", providerSource: "eventkit")

    // Full tier surfaces the real title + location.
    let full = try await service.getLinkedEventsForTask(taskID: task.id)
    let fullEvent = try XCTUnwrap(full.first)
    XCTAssertEqual(fullEvent.title, "Dentist")
    XCTAssertEqual(fullEvent.location, "123 Main St")

    // busy_only: occupancy still surfaces, but every detail field is redacted.
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .busyOnly)
    }
    let busy = try await service.getLinkedEventsForTask(taskID: task.id)
    let busyEvent = try XCTUnwrap(busy.first)
    XCTAssertEqual(
      busyEvent.id, "eventkit:device:ek-1", "occupancy still surfaces, only detail is redacted")
    XCTAssertEqual(busyEvent.title, "Busy")
    XCTAssertNil(busyEvent.location)

    // off: no linked provider event at all.
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .off)
    }
    let off = try await service.getLinkedEventsForTask(taskID: task.id)
    XCTAssertTrue(off.isEmpty, "off tier exposes no linked provider events")
  }

  func testProviderLinkRejectsUnknownProviderEvent() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Prep for missing event", notes: "")

    do {
      _ = try await service.linkTaskToProviderEvent(
        taskID: task.id,
        providerEventID: "missing-provider-event",
        providerSource: "eventkit")
      XCTFail("Expected unknown provider events to be rejected.")
    } catch {
      XCTAssertTrue(String(describing: error).contains("Provider event"))
    }
  }

  // MARK: - Scope toggle / clear

  // MARK: - Privacy: detail downgrade purges stale full-detail rows

  func testFullToBusyDowngradeScrubsProviderFocusTitleWithoutSyncWrite() async throws {
    let service = try makeService()
    let date = "2026-06-20"
    try await optIntoFullDetailTier(service)
    try await saveProviderFocusSchedule(service, date: date)
    let fullHuman = try await service.loadFocusSchedule(date: date)
    let fullAI = try await service.loadFocusScheduleForAI(date: date)
    XCTAssertEqual(fullHuman?.blocks.first?.title, "Private appointment")
    XCTAssertEqual(fullAI?.blocks.first?.title, "Private appointment")
    let before = try focusScheduleSyncState(service, date: date)

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)

    let human = try await service.loadFocusSchedule(date: date)
    XCTAssertEqual(human?.blocks.count, 1)
    XCTAssertEqual(human?.blocks.first?.title, "Event")
    let ai = try await service.loadFocusScheduleForAI(date: date)
    XCTAssertEqual(ai?.blocks.count, 1)
    XCTAssertEqual(ai?.blocks.first?.title, "Event")
    XCTAssertEqual(try focusScheduleSyncState(service, date: date).version, before.version)
    XCTAssertEqual(try focusScheduleSyncState(service, date: date).payload, before.payload)
  }

  func testFullToOffDowngradeScrubsStoredTitleAndOmitsOnlyProviderBlockFromAIRead()
    async throws
  {
    let service = try makeService()
    let date = "2026-06-21"
    try await optIntoFullDetailTier(service)
    try await saveProviderFocusSchedule(service, date: date, includeFreeform: true)
    let before = try focusScheduleSyncState(service, date: date)

    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.off.asString)

    let human = try await service.loadFocusSchedule(date: date)
    XCTAssertEqual(human?.blocks.count, 2, "human UI reads must retain hidden provider blocks")
    XCTAssertEqual(human?.blocks.first?.title, "Event")
    let ai = try await service.loadFocusScheduleForAI(date: date)
    XCTAssertEqual(ai?.blocks.map(\.title), ["Authored hold"])
    XCTAssertEqual(ai?.blocks.first?.eventSource, .freeform)
    let after = try focusScheduleSyncState(service, date: date)
    XCTAssertEqual(after.version, before.version)
    XCTAssertEqual(after.payload, before.payload)
  }

  /// Deleting the key resolves the tier to the domain default (`full_details`),
  /// which does not narrow exposure, so no scrub runs and the stored provider
  /// title survives on both the human and AI projections.
  func testDeletingAccessPreferenceKeepsProviderFocusTitleWhenDefaultDoesNotNarrow()
    async throws
  {
    let service = try makeService()
    let date = "2026-06-22"
    try await optIntoFullDetailTier(service)
    try await saveProviderFocusSchedule(service, date: date)
    let before = try focusScheduleSyncState(service, date: date)

    try await service.deletePreference(key: PreferenceKeys.devCalendarAiAccessMode)

    let human = try await service.loadFocusSchedule(date: date)
    let ai = try await service.loadFocusScheduleForAI(date: date)
    XCTAssertEqual(human?.blocks.first?.title, "Private appointment")
    XCTAssertEqual(ai?.blocks.first?.title, "Private appointment")
    let after = try focusScheduleSyncState(service, date: date)
    XCTAssertEqual(after.version, before.version)
    XCTAssertEqual(after.payload, before.payload)
  }

  func testSystemIntentFocusReadUsesAIProjectionWithoutMutatingHumanSchedule() async throws {
    let service = try makeService()
    let date = "2026-06-23"
    try await optIntoFullDetailTier(service)
    try await saveProviderFocusSchedule(service, date: date, includeFreeform: true)

    // Bypass the downgrade scrub to exercise read-layer defense in depth.
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .busyOnly)
    }
    let busy = try await LorvexSystemIntentRunner.readFocusSchedule(date: date, core: service)
    let humanUnderBusy = try await service.loadFocusSchedule(date: date)
    XCTAssertEqual(busy?.blocks.map(\.title), ["Event", "Authored hold"])
    XCTAssertEqual(
      humanUnderBusy?.blocks.first?.title,
      "Private appointment", "AI projection must not mutate the human-facing stored schedule")

    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .off)
    }
    let off = try await LorvexSystemIntentRunner.readFocusSchedule(date: date, core: service)
    let humanUnderOff = try await service.loadFocusSchedule(date: date)
    XCTAssertEqual(off?.blocks.map(\.title), ["Authored hold"])
    XCTAssertEqual(humanUnderOff?.blocks.count, 2)
  }

  /// A tier downgrade that reduces detail (fullDetails → busyOnly) must not
  /// leave previously-mirrored full-detail rows (real titles, locations,
  /// attendees) at rest for any window. Ingest reconciliation only ever rewrote
  /// the current window, so older browsed windows kept verbatim detail that the
  /// timeline / search reads (which pass `.fullDetails`) still served. The
  /// downgrade must purge the entire EventKit mirror, not just the live window.
  func testDetailDowngradePurgesStaleFullDetailRowsFromAllWindows() async throws {
    let service = try makeService()
    // Pin full detail explicitly so the subsequent busyOnly write is a real
    // detail-reducing downgrade whatever the domain default happens to be.
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)

    // Window A (June 1–5): a full-detail event with a real title + location.
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    // Window B (June 10–14): a separately-browsed window with organizer/attendees.
    let windowBEvent = EventKitFetchedEvent(
      key: "ek-b", title: "Board meeting", notes: "confidential",
      startDate: "2026-06-12", startTime: "09:00", endDate: "2026-06-12", endTime: "10:00",
      allDay: false, location: "HQ", timezone: "America/Los_Angeles",
      organizerEmail: "chair@example.com",
      attendees: [EventKitFetchedAttendee(email: "chair@example.com", status: .accepted)])
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: [windowBEvent], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-10", windowEnd: "2026-06-14")

    // Both windows' full detail is live before the downgrade.
    let before = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-14")
    XCTAssertTrue(before.events.contains { $0.title == "Dentist" })
    XCTAssertTrue(before.events.contains { $0.title == "Board meeting" })

    // Downgrade the persisted access mode to busyOnly.
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)

    // Every cached provider row is purged — timeline and search no longer serve
    // the real titles / attendees for ANY window, including the older one that
    // ingest reconciliation would never have revisited.
    let after = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-14")
    XCTAssertFalse(
      after.events.contains { $0.source == "provider" },
      "downgrade must purge all cached provider rows, not just the current window")
    XCTAssertFalse(after.events.contains { $0.title == "Dentist" || $0.title == "Board meeting" })

    let dentistHits = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertTrue(dentistHits.isEmpty, "stale full-detail title must not survive downgrade in search")
    let boardHits = try await service.searchCalendarEvents(
      query: "Board meeting", from: nil, to: nil, limit: nil)
    XCTAssertTrue(boardHits.isEmpty, "stale attendees must not survive downgrade in search")
  }

  /// Deleting the `calendar_ai_access_mode` key clears the device-state row, so
  /// readers fall back to the domain default (`full_details`). That fallback
  /// widens rather than narrows exposure, so the delete is not a downgrade and
  /// the mirrored provider detail must survive it — the timeline and search
  /// keep serving what is already at rest. The purge is keyed off `defaultMode`
  /// rather than a fixed direction, so it would still fire on this path if the
  /// default were ever narrowed; the explicit-downgrade tests cover that branch.
  func testDeleteAccessModeKeyKeepsMirrorWhenDefaultDoesNotNarrow() async throws {
    let service = try makeService()
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    let before = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertTrue(before.events.contains { $0.title == "Dentist" })

    // Deleting the key falls back to full_details — no reduction in exposure.
    try await service.deletePreference(key: PreferenceKeys.devCalendarAiAccessMode)

    let after = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertTrue(
      after.events.contains { $0.title == "Dentist" },
      "the default fallback does not narrow exposure, so the mirror must survive the delete")
    let hits = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertFalse(hits.isEmpty, "provider detail must stay searchable after the delete")
  }

  /// FIX 2 (ingest TOCTOU): the coordinator reads the tier and fetches from
  /// EventKit OUT of transaction, so a privacy downgrade can commit — purging
  /// the mirror and disabling the scope — between building the (still
  /// full-detail) rows and committing the ingest. `ingestEventKitEvents` re-reads
  /// the persisted tier inside the write transaction and aborts when it is now
  /// stricter than the tier the rows were built at, so the pre-downgrade
  /// full-detail rows never land at rest and the disabled scope is not silently
  /// re-enabled.
  func testIngestAbortsWhenTierDowngradesBetweenBuildAndCommit() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)

    // A full-detail row is already at rest, scope enabled + refreshed.
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    XCTAssertTrue(try eventKitScopeSurfaces(service))

    // The coordinator captured a fresh full-detail batch before its slow
    // EventKit fetch (still built at full detail).
    let staleFullDetailRows = EventKitIngest.providerRows(
      from: fetched(), scope: "device", accessMode: .fullDetails)

    // A privacy downgrade commits mid-fetch: busy_only is persisted, and the
    // downgrade purges the mirror + disables the EventKit scope.
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)
    XCTAssertFalse(try eventKitScopeSurfaces(service))

    // The stale full-detail rows now try to commit. The in-transaction tier
    // re-read (busy_only < full_details) aborts the write.
    let count = try service.ingestEventKitEvents(
      staleFullDetailRows, builtAtMode: .fullDetails,
      windowStart: "2026-06-01", windowEnd: "2026-06-05")
    XCTAssertEqual(
      count, 0, "ingest must abort when the persisted tier is stricter than the build tier")

    // No full-detail rows persisted: the full-detail timeline / search read
    // surfaces nothing.
    let timeline = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertFalse(timeline.events.contains { $0.source == "provider" })
    let search = try await service.searchCalendarEvents(
      query: "Dentist", from: nil, to: nil, limit: nil)
    XCTAssertFalse(search.contains { $0.source == "provider" })

    // The scope the downgrade disabled was NOT re-enabled by the aborted ingest.
    XCTAssertFalse(
      try eventKitScopeSurfaces(service),
      "aborted ingest must not re-enable the scope the downgrade disabled")
  }

  // MARK: - Privacy: read-layer redaction honors the effective tier at rest

  /// FIX 2 (read-layer redaction): `loadCalendarTimeline` honors the effective
  /// calendar AI-access tier read from `device_state`, so a full-detail provider
  /// row that survives at rest under a reduced tier is still redacted on read —
  /// defense in depth behind ingest-time redaction + downgrade purge. The tier is
  /// flipped to `busy_only` with a direct `device_state` write (NOT via
  /// `setPreference`, which would purge the mirror) so a full-detail row remains
  /// at rest for the read to redact.
  func testTimelineReadRedactsSurvivingFullDetailRowUnderBusyTier() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(
        from: attendeeFetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    // Full detail is at rest and visible under the pinned full tier.
    let before = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let beforeEvent = try XCTUnwrap(before.events.first { $0.source == "provider" })
    XCTAssertEqual(beforeEvent.title, "Design sync")
    XCTAssertNotNil(beforeEvent.attendees)

    // Flip the effective tier to busy_only WITHOUT the downgrade purge, so the
    // full-detail row survives at rest (a mirror the purge / re-ingest missed).
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .busyOnly)
    }

    let after = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let afterEvent = try XCTUnwrap(after.events.first { $0.source == "provider" })
    XCTAssertEqual(afterEvent.title, "Busy")
    XCTAssertNil(afterEvent.location)
    XCTAssertNil(afterEvent.attendees)
    XCTAssertNil(afterEvent.personName)
    XCTAssertNil(afterEvent.notes)
  }

  /// FIX 2 (read-layer redaction), focus path: `proposeFocusSchedule` reads the
  /// effective tier from `device_state` too, so a full-detail provider row at
  /// rest under `busy_only` surfaces in the day's proposal as redacted occupancy
  /// ("Busy"), never the real event title.
  func testFocusProposalRedactsSurvivingFullDetailRowUnderBusyTier() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    // Pin the anchor timezone so the event's minute-of-day is deterministic.
    _ = try await service.setPreference(key: PreferenceKeys.prefTimezone, value: "UTC")

    let task = try await service.createTask(title: "Write report", notes: "")
    _ = try await service.setCurrentFocus(
      date: "2026-06-02", taskIDs: [task.id], briefing: nil, timezone: "UTC")

    // A full-detail event at 09:00–10:00 UTC (the working-hours start), so it
    // packs into the proposal as an event block.
    let event = EventKitFetchedEvent(
      key: "ek-focus", title: "Board meeting", notes: "confidential",
      startDate: "2026-06-02", startTime: "09:00", endDate: "2026-06-02", endTime: "10:00",
      allDay: false, location: "HQ", timezone: "UTC")
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")

    // Full detail surfaces in the proposal under the pinned full tier.
    let before = try await service.proposeFocusSchedule(date: "2026-06-02")
    let fullDetailBlock = try XCTUnwrap(before.blocks.first { $0.title == "Board meeting" })
    XCTAssertEqual(fullDetailBlock.eventSource, .provider)
    XCTAssertNil(fullDetailBlock.calendarEventID)

    // Flip to busy_only WITHOUT the downgrade purge, leaving the full-detail row
    // at rest.
    try service.write { db in
      try DeviceStateRepo.writeCalendarAiAccessMode(db, mode: .busyOnly)
    }

    let after = try await service.proposeFocusSchedule(date: "2026-06-02")
    XCTAssertFalse(
      after.blocks.contains { $0.title == "Board meeting" },
      "focus proposal must redact a full-detail provider row at rest under a busy tier")
    let redactedBlock = try XCTUnwrap(after.blocks.first { $0.title == "Busy" })
    XCTAssertEqual(redactedBlock.eventSource, .provider)
    XCTAssertNil(redactedBlock.calendarEventID)
  }

  func testOverlappingCanonicalAndProviderScheduleRoundTripRetainsProvenanceAtOff()
    async throws
  {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try await service.setPreference(key: PreferenceKeys.prefTimezone, value: "UTC")
    let date = "2026-06-02"
    let task = try await service.createTask(title: "Write report", notes: "")
    _ = try await service.setCurrentFocus(
      date: date, taskIDs: [task.id], briefing: nil, timezone: "UTC")
    let canonical = try await service.createCalendarEvent(
      title: "Canonical review", startDate: date, endDate: nil,
      startTime: "09:30", endTime: "10:30", allDay: false,
      location: nil, notes: nil)
    let provider = EventKitFetchedEvent(
      key: "ek-overlap", title: "Private appointment", notes: nil,
      startDate: date, startTime: "10:00", endDate: date, endTime: "11:00",
      allDay: false, location: nil, timezone: "UTC")
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(
        from: [provider], scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: date, windowEnd: date)

    let proposed = try await service.proposeFocusSchedule(date: date)
    let proposedEvents = proposed.blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(proposedEvents.count, 2)
    XCTAssertTrue(
      proposedEvents.contains {
        $0.eventSource == .canonical && $0.calendarEventID == canonical.id
          && $0.title == "Canonical review"
      })
    XCTAssertTrue(
      proposedEvents.contains {
        $0.eventSource == .provider && $0.calendarEventID == nil
          && $0.title == "Private appointment"
      })

    _ = try await service.saveFocusSchedule(
      date: date, blocks: proposed.blocks, rationale: nil)
    _ = try await service.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.off.asString)

    let human = try await service.loadFocusSchedule(date: date)
    let humanEvents = try XCTUnwrap(human).blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(humanEvents.count, 2, "human schedule keeps both stored event blocks")
    XCTAssertTrue(
      humanEvents.contains {
        $0.eventSource == .canonical && $0.calendarEventID == canonical.id
          && $0.title == "Canonical review"
      })
    XCTAssertTrue(
      humanEvents.contains {
        $0.eventSource == .provider && $0.calendarEventID == nil && $0.title == "Event"
      })

    let ai = try await service.loadFocusScheduleForAI(date: date)
    let aiEvents = try XCTUnwrap(ai).blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(aiEvents.count, 1)
    XCTAssertEqual(aiEvents.first?.eventSource, .canonical)
    XCTAssertEqual(aiEvents.first?.calendarEventID, canonical.id)
    XCTAssertEqual(aiEvents.first?.title, "Canonical review")
  }

  func testDisableScopeHidesMirroredRows() async throws {
    let service = try makeService()
    try await optIntoFullDetailTier(service)
    _ = try service.ingestEventKitEvents(
      EventKitIngest.providerRows(from: fetched(), scope: "device", accessMode: .fullDetails),
      builtAtMode: .fullDetails, windowStart: "2026-06-01", windowEnd: "2026-06-05")
    try service.setEventKitScopeEnabled(false)

    let snapshot = try await service.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    XCTAssertFalse(snapshot.events.contains { $0.source == "provider" })
  }
}
