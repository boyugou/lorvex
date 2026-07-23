import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Creates an editable Lorvex-owned event inside the store's calendar window
/// (which spans around today, so the fixed 2026-05-22 seed event is outside
/// it) and returns the stored event.
private func seedTimelineEvent(
  _ core: SwiftLorvexCoreService, title: String = "Window review",
  startTime: String = "15:00", endTime: String = "15:45"
) async throws -> CalendarTimelineEvent {
  try await core.createCalendarEvent(
    title: title, startDate: LorvexDateFormatters.ymd.string(from: Date()), endDate: nil,
    startTime: startTime, endTime: endTime, allDay: false, location: "Conference Room B",
    notes: nil)
}

@MainActor
private func makeCoordinator(
  access: FakeEventKitAccess = FakeEventKitAccess(),
  provider: FakeEventKitProvider = FakeEventKitProvider(),
  enabled: Bool = true,
  calendarFilter: EventKitCalendarFilter = .all
) -> EventKitCoordinator {
  EventKitCoordinator(
    access: access,
    provider: provider,
    loadAccessMode: { .busyOnly },
    loadCalendarFilter: { calendarFilter },
    isEnabled: { enabled })
}

@Test
func calendarIntegrationReportSettingsStatusUsesLocalizationCatalog() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let settingsSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Views/SettingsCalendarSection.swift"),
    encoding: .utf8
  )
  let displaySource = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Support/CalendarIntegrationReportDisplay.swift"),
    encoding: .utf8
  )

  #expect(settingsSource.contains("SettingsCalendarStatusPanel("))
  #expect(settingsSource.contains("importReport.localizedSettingsStatus"))
  #expect(settingsSource.contains("exportReport.localizedSettingsStatus"))
  #expect(displaySource.contains(#""settings.calendar.status.not_started""#))
  #expect(displaySource.contains(#""settings.calendar.status.succeeded""#))
  #expect(displaySource.contains(#""settings.calendar.status.skipped""#))
  #expect(displaySource.contains(#""settings.calendar.status.failed""#))
}

@Test
func calendarIntegrationReportLocalizedSettingsStatusMatchesSourceFallbacks() {
  #expect(CalendarIntegrationReport.notStarted.localizedSettingsStatus == "Not Started")
  #expect(CalendarIntegrationReport.succeeded(operation: "eventkit-import", eventCount: 1).localizedSettingsStatus == "Succeeded")
  #expect(CalendarIntegrationReport.skipped(operation: "eventkit-export").localizedSettingsStatus == "Skipped")
  #expect(
    CalendarIntegrationReport.failed(
      operation: "eventkit-export",
      error: LorvexCoreError.unsupportedOperation("Calendar unavailable")
    ).localizedSettingsStatus == "Failed"
  )
}

@MainActor
@Test
func calendarEventSourceResolvesProviderEventLiveFromEventKit() async throws {
  let access = FakeEventKitAccess()
  await access.setEventSourceResult(
    EventKitEventSource(
      calendarTitle: "Holidays in United States",
      accountTitle: "iCloud"))
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))

  // A provider (system-calendar) event: id is the "kind:scope:key" composite,
  // and the cache only knows the opaque "provider" sentinel — so the fine-grained
  // calendar identity must come back live from EventKit.
  let providerEvent = CalendarTimelineEvent(
    id: "eventkit:device:evt-1", title: "Standup", source: "provider", editable: false,
    startDate: "2026-06-23", startTime: "09:00", endDate: "2026-06-23", endTime: "09:30",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let resolved = await store.calendarEventSource(for: providerEvent)
  #expect(resolved?.calendarTitle == "Holidays in United States")
  #expect(resolved?.accountTitle == "iCloud")

  // Lorvex-owned (editable) events never resolve through the provider path.
  let ownedEvent = CalendarTimelineEvent(
    id: "owned-uuid", title: "1111", source: "canonical", editable: true,
    startDate: "2026-06-24", startTime: "12:00", endDate: "2026-06-24", endTime: "13:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  #expect(await store.calendarEventSource(for: ownedEvent) == nil)
}

@MainActor
@Test
func recurringProviderOccurrenceResolvesSourceWithStableEventAddress() async throws {
  let access = FakeEventKitAccess()
  await access.setEventSourceResult(
    EventKitEventSource(calendarTitle: "Work", accountTitle: "iCloud"))
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))
  let occurrence = CalendarTimelineEvent(
    id: "eventkit:device:opaque:key:occurrence:2026-06-24",
    eventID: "eventkit:device:opaque:key",
    title: "Recurring standup", source: "provider", editable: false,
    startDate: "2026-06-24", startTime: "09:00", endDate: "2026-06-24",
    endTime: "09:30", allDay: false, location: nil, color: nil,
    eventType: "event", timezone: "UTC", isRecurring: true)

  let resolved = await store.calendarEventSource(for: occurrence)

  #expect(resolved?.calendarTitle == "Work")
  #expect(await access.recordedEventSourceLookups() == ["opaque:key"])
}

@Test
func eventKitCoordinatorRebindsProviderAfterCoreStorageSwitch() async throws {
  let oldProvider = FakeEventKitProvider()
  let newProvider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: FakeEventKitAccess(),
    provider: oldProvider,
    loadAccessMode: { .fullDetails },
    isEnabled: { true }
  )
  let start = Date(timeIntervalSince1970: 1_779_465_600)
  let end = start.addingTimeInterval(1_800)

  _ = try await coordinator.writeBack(
    taskID: "task-old",
    existingKey: nil,
    lorvexEventID: "calendar-old",
    title: "Before storage switch",
    start: start,
    end: end,
    isAllDay: false,
    location: nil,
    notes: nil
  )
  await coordinator.updateProvider(newProvider)
  _ = try await coordinator.writeBack(
    taskID: "task-new",
    existingKey: nil,
    lorvexEventID: "calendar-new",
    title: "After storage switch",
    start: start,
    end: end,
    isAllDay: false,
    location: nil,
    notes: nil
  )

  #expect(oldProvider.recordedLinks().map(\.taskID) == ["task-old"])
  #expect(newProvider.recordedLinks().map(\.taskID) == ["task-new"])
}

@Test
func eventKitIngestClearsMirrorWhenReadAccessIsRevoked() async throws {
  let access = FakeEventKitAccess()
  await access.setReadAuthorizationState(.unavailable)
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access,
    provider: provider,
    loadAccessMode: { .fullDetails },
    isEnabled: { true }
  )

  await #expect(throws: EventKitAccessError.readAccessDenied) {
    try await coordinator.ingest(
      from: Date(timeIntervalSince1970: 1_779_465_600),
      to: Date(timeIntervalSince1970: 1_779_552_000))
  }
  #expect(provider.clearCount == 1)
}

@Test
func eventKitIngestKeepsMirrorForStalePostGrantNotDeterminedRead() async throws {
  let access = FakeEventKitAccess()
  await access.setReadAuthorizationState(.staleNotDeterminedGrant)
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access,
    provider: provider,
    loadAccessMode: { .fullDetails },
    isEnabled: { true }
  )

  _ = try await coordinator.ingest(
    from: Date(timeIntervalSince1970: 1_779_465_600),
    to: Date(timeIntervalSince1970: 1_779_552_000))
  #expect(provider.clearCount == 0)
}

@Test
func eventKitIngestPreservesExplicitProductDayWindowLabels() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access,
    provider: provider,
    loadAccessMode: { .fullDetails },
    isEnabled: { true }
  )

  _ = try await coordinator.ingest(
    from: Date(timeIntervalSince1970: 1_779_465_600),
    to: Date(timeIntervalSince1970: 1_779_552_000),
    windowStart: "2026-05-22",
    windowEnd: "2026-06-05")

  #expect(provider.ingestedWindows.count == 1)
  #expect(provider.ingestedWindows.first?.start == "2026-05-22")
  #expect(provider.ingestedWindows.first?.end == "2026-06-05")
  #expect(await access.recordedFetchWindowEndDays() == ["2026-06-05"])
}

@Test
func eventKitWriteBackDoesNotWriteWhenIntegrationDisabled() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let coordinator = EventKitCoordinator(
    access: access,
    provider: provider,
    loadAccessMode: { .fullDetails },
    isEnabled: { false }
  )
  let start = Date(timeIntervalSince1970: 1_779_465_600)

  await #expect(throws: EventKitAccessError.integrationDisabled) {
    try await coordinator.writeBack(
      taskID: "task-disabled",
      existingKey: nil,
      lorvexEventID: "calendar-disabled",
      title: "Disabled write",
      start: start,
      end: start.addingTimeInterval(1_800),
      isAllDay: false,
      location: nil,
      notes: nil)
  }

  #expect(await access.recordedWrites().isEmpty)
  #expect(provider.recordedLinks().isEmpty)
}

@MainActor
@Test
func appStoreCreatesPreviewCalendarEvent() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))
  var components = DateComponents()
  components.calendar = Calendar(identifier: .gregorian)
  components.timeZone = .current
  components.year = 2026
  components.month = 5
  components.day = 22
  components.hour = 10
  components.minute = 0
  let startDate = try #require(components.date)
  components.hour = 10
  components.minute = 30
  let endDate = try #require(components.date)

  await store.refresh()
  store.draftCalendarTitle = "Native planning block"
  store.draftCalendarDate = startDate
  store.draftCalendarStartTime = startDate
  store.draftCalendarEndTime = endDate
  store.draftCalendarLocation = "Studio"
  store.draftCalendarNotes = "Created from the Apple app."
  await store.createDraftCalendarEvent()

  // The event landed in the canonical timeline + was written back into the
  // dedicated Lorvex calendar via the coordinator.
  #expect(store.calendarTimeline?.events.contains { $0.title == "Native planning block" } == true)
  let writes = await access.recordedWrites()
  #expect(writes.contains { $0.title == "Native planning block" })
  #expect(store.lastCalendarExportReport.status == .succeeded)
  #expect(store.lastCalendarExportReport.eventCount == 1)
  #expect(store.draftCalendarTitle == "")
  #expect(store.selection == .calendar)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreUpdatesEditableCalendarEventThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await seedTimelineEvent(core)
  let store = AppStore(core: core, eventKitCoordinator: makeCoordinator())
  var components = Calendar(identifier: .gregorian).dateComponents(
    [.year, .month, .day], from: Date())
  components.calendar = Calendar(identifier: .gregorian)
  components.timeZone = .current
  components.hour = 9
  components.minute = 15
  let startDate = try #require(components.date)
  components.hour = 10
  components.minute = 0
  let endDate = try #require(components.date)

  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })
  store.prepareCalendarDraft(for: event)
  store.draftCalendarTitle = "  Native calendar review  "
  store.draftCalendarDate = startDate
  store.draftCalendarStartTime = startDate
  store.draftCalendarEndTime = endDate
  store.draftCalendarLocation = "  Design Studio  "

  await store.updateCalendarEvent(event)

  let updated = try #require(store.calendarTimeline?.events.first { $0.id == event.id })
  #expect(updated.title == "Native calendar review")
  #expect(updated.startDate == LorvexDateFormatters.ymd.string(from: Date()))
  #expect(updated.startTime == "09:15")
  #expect(updated.endTime == "10:00")
  #expect(updated.location == "Design Studio")
  #expect(store.draftCalendarTitle == "")
  #expect(store.selection == .calendar)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreFullCalendarEditorCanClearOptionalFields() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await core.createCalendarEvent(
    title: "Fields to clear", startDate: LorvexDateFormatters.ymd.string(from: Date()),
    endDate: nil, startTime: "09:00", endTime: "09:30", allDay: false,
    location: "Room 4", notes: "Bring the draft", recurrence: nil,
    timezone: nil, url: nil, color: "#336699", eventType: nil,
    personName: nil, attendees: nil)
  let store = AppStore(core: core, eventKitCoordinator: makeCoordinator())
  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })
  store.prepareCalendarDraft(for: event)
  store.draftCalendarLocation = "   "
  store.draftCalendarNotes = "\n  "
  store.draftCalendarColor = nil

  await store.updateCalendarEvent(event)

  let updated = try #require(await core.getCalendarEvent(id: event.id))
  #expect(updated.location?.isEmpty == true)
  #expect(updated.notes?.isEmpty == true)
  #expect(updated.color == nil)
}

@MainActor
@Test
func prepareCalendarDraftKeepsExistingDraftWhenEventDatesAreInvalid() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let date = Date(timeIntervalSince1970: 1_779_494_400)
  let startTime = Date(timeIntervalSince1970: 1_779_530_400)
  let endTime = Date(timeIntervalSince1970: 1_779_534_000)
  store.draftCalendarDate = date
  store.draftCalendarStartTime = startTime
  store.draftCalendarEndTime = endTime

  store.prepareCalendarDraft(
    for: CalendarTimelineEvent(
      id: "bad-calendar-date",
      title: "Imported malformed event",
      source: "eventkit",
      editable: true,
      startDate: "not-a-date",
      startTime: "not-a-time",
      endDate: nil,
      endTime: "also-not-a-time",
      allDay: false,
      location: nil,
      color: nil,
      eventType: "event",
      timezone: nil,
      isRecurring: false
    ))

  #expect(store.draftCalendarTitle == "Imported malformed event")
  #expect(store.draftCalendarDate == date)
  #expect(store.draftCalendarStartTime == startTime)
  #expect(store.draftCalendarEndTime == startTime)
}

@Test
func prepareCalendarDraftDoesNotFallbackToDateNow() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Stores/AppStoreCalendarActions.swift"),
    encoding: .utf8)

  #expect(source.contains("func prepareCalendarDraft(for event: CalendarTimelineEvent)"))
  #expect(!source.contains("draftCalendarDate = Self.ymdFormatter.date(from: event.startDate) ?? Date()"))
  #expect(!source.contains("draftCalendarStartTime = event.startTime.flatMap(Self.hmFormatter.date(from:)) ?? Date()"))
}

@MainActor
@Test
func appStoreDeletesEditableCalendarEventThroughCore() async throws {
  let access = FakeEventKitAccess()
  let core = try await makeSeededInMemoryCore()
  let seeded = try await seedTimelineEvent(core)
  let store = AppStore(core: core, eventKitCoordinator: makeCoordinator(access: access))

  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })

  await store.deleteCalendarEvent(event)

  #expect(store.calendarTimeline?.events.contains { $0.id == event.id } == false)
  let deletes = await access.recordedDeletes()
  #expect(deletes.contains(event.id))
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreCalendarScheduledTasksUseFullTaskCorpus() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, eventKitCoordinator: makeCoordinator())

  await store.refresh()
  let scheduledDate = try #require(
    Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 19)))
  let task = try await core.importRemoteTask(
    id: UUID().uuidString.lowercased(),
    title: "Prepare flight day plan",
    notes: "",
    aiNotes: nil,
    priority: .p2,
    status: .open,
    estimatedMinutes: nil,
    plannedDate: scheduledDate,
    tags: [],
    dependsOn: []
  )

  #expect(store.today.tasks.contains { $0.id == task.id } == false)

  try await store.refreshCalendarTimeline(anchorDate: scheduledDate)

  #expect(store.calendarScheduledTasks?.contains { $0.id == task.id } == true)
  #expect(store.scheduledTasks.contains { $0.id == task.id })
}

@MainActor
@Test
func appStoreAddTaskToCalendarBindsLinkRow() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access, provider: provider))
  let taskDate = try #require(
    Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 20)))
  let task = try await store.core.importRemoteTask(
    id: UUID().uuidString.lowercased(),
    title: "Dated calendar task",
    notes: "",
    aiNotes: nil,
    priority: .p2,
    status: .open,
    estimatedMinutes: nil,
    plannedDate: taskDate,
    tags: [],
    dependsOn: []
  )

  #expect(store.canAddTaskToCalendar)
  #expect(store.canAddTaskToCalendar(task))
  await store.addTaskToCalendar(task)

  // The task was written into the Lorvex calendar and bound via a link row.
  let writes = await access.recordedWrites()
  #expect(writes.contains { $0.lorvexID != "" })
  let links = provider.recordedLinks()
  #expect(links.contains { $0.taskID == task.id })
  #expect(store.lastCalendarExportReport.status == .succeeded)
}

@MainActor
@Test
func appStoreDoesNotAddUndatedTaskToCalendarAsToday() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    eventKitCoordinator: makeCoordinator(access: access, provider: provider))
  let task = try await core.importRemoteTask(
    id: UUID().uuidString.lowercased(),
    title: "Undated calendar task",
    notes: "",
    aiNotes: nil,
    priority: .p2,
    status: .open,
    estimatedMinutes: nil,
    plannedDate: nil,
    tags: [],
    dependsOn: []
  )

  #expect(!store.canAddTaskToCalendar(task))
  await store.addTaskToCalendar(task)

  #expect((await access.recordedWrites()).isEmpty)
  #expect(provider.recordedLinks().isEmpty)
  #expect(store.lastCalendarExportReport.status == .skipped)
  #expect(store.errorMessage?.contains("planned date") == true)
}

@MainActor
@Test
func appStoreDoesNotAddTaskToCalendarWhenExistingLinkLookupFails() async throws {
  let access = FakeEventKitAccess()
  let provider = FakeEventKitProvider()
  provider.eventKitLinksForTaskError = LorvexCoreError.unsupportedOperation("Link lookup failed.")
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    eventKitCoordinator: makeCoordinator(access: access, provider: provider))
  let taskDate = try #require(
    Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 20)))
  let task = try await core.importRemoteTask(
    id: UUID().uuidString.lowercased(),
    title: "Link lookup failure task",
    notes: "",
    aiNotes: nil,
    priority: .p2,
    status: .open,
    estimatedMinutes: nil,
    plannedDate: taskDate,
    tags: [],
    dependsOn: []
  )

  await store.addTaskToCalendar(task)

  #expect((await access.recordedWrites()).isEmpty)
  #expect(provider.recordedLinks().isEmpty)
  #expect(store.lastCalendarExportReport.status == .failed)
  #expect(store.errorMessage?.contains("Link lookup failed") == true)
}

@Test
func addTaskToCalendarDoesNotFallbackToDateNow() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let source = try String(
    contentsOf: root.appending(path: "Sources/LorvexApple/Stores/AppStoreCalendarWriteBack.swift"),
    encoding: .utf8)

  #expect(source.contains("guard let day = task.plannedDate"))
  #expect(!source.contains("task.plannedDate ?? Date()"))
}

@MainActor
@Test
func eventKitCoordinatorPassesCalendarFilterToAccessLayer() async throws {
  let access = FakeEventKitAccess()
  let filter = EventKitCalendarFilter(
    includedCalendarIDs: ["work-calendar"],
    excludedCalendarIDs: ["private-calendar"])
  let coordinator = makeCoordinator(access: access, calendarFilter: filter)

  _ = try await coordinator.ingest(from: Date(), to: Date().addingTimeInterval(3600))

  let recorded = await access.fetchCalendarFilters
  #expect(recorded == [filter])
}

@MainActor
@Test
func eventKitCoordinatorIngestDoesNotPromptByDefault() async throws {
  let access = FakeEventKitAccess()
  let coordinator = makeCoordinator(access: access)

  _ = try await coordinator.ingest(from: Date(), to: Date().addingTimeInterval(3600))

  let requestCount = await access.recordedRequestAccessCount()
  #expect(requestCount == 0)
}

@MainActor
@Test
func eventKitCoordinatorIngestCanRequestAccessForUserInitiatedSettingsActions() async throws {
  let access = FakeEventKitAccess()
  let coordinator = makeCoordinator(access: access)

  _ = try await coordinator.ingest(
    from: Date(), to: Date().addingTimeInterval(3600), requestAccess: true)

  let requestCount = await access.recordedRequestAccessCount()
  #expect(requestCount == 1)
}

@MainActor
@Test
func appStoreLoadsEventKitCalendarsThroughCoordinator() async throws {
  let access = FakeEventKitAccess()
  await access.setAvailableCalendars([
    EventKitCalendarDescriptor(id: "work", title: "Work", sourceTitle: "iCloud")
  ])
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))

  let calendars = try await store.loadEventKitCalendars()

  #expect(calendars == [
    EventKitCalendarDescriptor(id: "work", title: "Work", sourceTitle: "iCloud")
  ])
}

@MainActor
@Test
func appStoreLoadsWritableEventKitCalendarsThroughCoordinator() async throws {
  let access = FakeEventKitAccess()
  await access.setWritableCalendars([
    EventKitCalendarDescriptor(id: "work", title: "Work", sourceTitle: "iCloud", colorHex: "#00FF00")
  ])
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))

  let calendars = try await store.loadWritableEventKitCalendars()

  #expect(calendars.map(\.id) == ["work"])
  #expect(calendars.first?.colorHex == "#00FF00")
}

@MainActor
@Test
func appStoreCreateCalendarEventTargetsChosenCalendar() async throws {
  let access = FakeEventKitAccess()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))
  await store.refresh()
  store.draftCalendarTitle = "Filed elsewhere"
  store.draftCalendarAllDay = true
  store.draftCalendarTargetCalendarID = "work"

  await store.createDraftCalendarEvent()

  // The user's calendar choice reaches the EventKit write-back as an explicit
  // target rather than the Lorvex default.
  let targets = await access.recordedWriteTargets()
  #expect(targets == [.calendar(id: "work")])
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreResolvesEditDraftTargetCalendarFromMirror() async throws {
  let access = FakeEventKitAccess()
  await access.setLorvexEventCalendarID("work")
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: makeCoordinator(access: access))
  let event = CalendarTimelineEvent(
    id: "evt-edit", title: "Standup", source: "lorvex", editable: true,
    startDate: "2030-01-02", startTime: "09:00", endDate: nil, endTime: "09:30",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  store.selectCalendarEvent(event)

  await store.resolveDraftTargetCalendar(for: event)

  #expect(store.draftCalendarTargetCalendarID == "work")
}

// MARK: - CalendarEventExport mapping (pure)

@Test
func calendarEventExportMapsAllDayAndTimedEvents() throws {
  let timed = CalendarTimelineEvent(
    id: "event-timed", title: "Native planning block", source: "lorvex", editable: true,
    startDate: "2030-05-23", startTime: "10:00", endDate: nil, endTime: "10:30",
    allDay: false, location: "Studio", color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let timedExport = try #require(CalendarEventExport(event: timed, notes: "Prepare"))
  #expect(timedExport.title == "Native planning block")
  #expect(timedExport.isAllDay == false)
  #expect(timedExport.location == "Studio")
  #expect(timedExport.notes == "Prepare")
  #expect(timedExport.endDate > timedExport.startDate)

  let allDay = CalendarTimelineEvent(
    id: "event-all-day", title: "Design review", source: "lorvex", editable: true,
    startDate: "2030-05-24", startTime: nil, endDate: nil, endTime: nil,
    allDay: true, location: "  ", color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let allDayExport = try #require(CalendarEventExport(event: allDay, notes: "  "))
  #expect(allDayExport.isAllDay)
  #expect(allDayExport.location == nil)
  #expect(allDayExport.notes == nil)
  #expect(allDayExport.endDate.timeIntervalSince(allDayExport.startDate) == 24 * 60 * 60)

  let multiDay = CalendarTimelineEvent(
    id: "event-all-day-span", title: "Conference", source: "lorvex", editable: true,
    startDate: "2030-05-24", startTime: nil, endDate: "2030-05-26", endTime: nil,
    allDay: true, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let multiDayExport = try #require(CalendarEventExport(event: multiDay, notes: nil))
  #expect(multiDayExport.endDate.timeIntervalSince(multiDayExport.startDate) == 3 * 24 * 60 * 60)
}

@Test
func calendarEventExportRollsCrossMidnightNilEndDateToNextDay() throws {
  // Timed event with no endDate and an endTime that is at/before the start time
  // on the start day (22:00 → 00:00) crosses midnight. The export must roll the
  // end into the next day, not collapse it via the 5-minute floor to a tiny
  // sub-minute event.
  let crossMidnight = CalendarTimelineEvent(
    id: "event-cross-midnight", title: "Late session", source: "lorvex", editable: true,
    startDate: "2030-05-23", startTime: "22:00", endDate: nil, endTime: "00:00",
    allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
    isRecurring: false)
  let export = try #require(CalendarEventExport(event: crossMidnight, notes: nil))
  // 22:00 → next-day 00:00 == a 2-hour event, not a collapsed 5-minute one.
  #expect(export.endDate.timeIntervalSince(export.startDate) == 2 * 60 * 60)
}

// MARK: - Drag-to-reschedule (week-grid drag-to-move / drag-to-resize)

@MainActor
@Test
func rescheduleCalendarEventShiftsStartAndEndTimes() async throws {
  let core = try await makeSeededInMemoryCore()
  let seeded = try await seedTimelineEvent(core)
  let store = AppStore(core: core, eventKitCoordinator: makeCoordinator())
  await store.refresh()
  let original = try #require(
    store.calendarTimeline?.events.first { $0.id == seeded.id })

  var comps = Calendar(identifier: .gregorian).dateComponents(
    [.year, .month, .day], from: Date())
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.hour = 11; comps.minute = 30
  let newStart = try #require(comps.date)
  comps.hour = 13; comps.minute = 0
  let newEnd = try #require(comps.date)

  await store.rescheduleCalendarEvent(original, newStart: newStart, newEnd: newEnd)

  let updated = try #require(store.calendarTimeline?.events.first { $0.id == original.id })
  #expect(updated.startDate == LorvexDateFormatters.ymd.string(from: Date()))
  #expect(updated.startTime == "11:30")
  #expect(updated.endTime == "13:00")
  #expect(updated.title == original.title)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func rescheduleCalendarEventIgnoresNonEditableEvent() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(), eventKitCoordinator: makeCoordinator())
  await store.refresh()
  let frozen = CalendarTimelineEvent(
    id: "external-mirror", title: "Vendor sync", source: "eventkit", editable: false,
    startDate: "2026-05-22", startTime: "10:00", endDate: nil, endTime: "11:00",
    allDay: false, location: nil, color: nil, eventType: "event",
    timezone: nil, isRecurring: false)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian); comps.timeZone = .current
  comps.year = 2026; comps.month = 5; comps.day = 22; comps.hour = 14; comps.minute = 0
  let newStart = try #require(comps.date)
  comps.hour = 15
  let newEnd = try #require(comps.date)

  await store.rescheduleCalendarEvent(frozen, newStart: newStart, newEnd: newEnd)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func rescheduleCalendarEventSkipsMultiDayEvents() async throws {
  // Multi-day events (e.g. Mon 23:00 → Tue 01:00) render as per-day clips
  // in the week grid; the drag-gesture math operates on the clip, not the
  // event, so applying a reschedule would write garbage start/end. The
  // store-side guard is defense in depth around the view-side gesture skip.
  let store = AppStore(
    core: try await makeSeededInMemoryCore(), eventKitCoordinator: makeCoordinator())
  await store.refresh()
  let multiDay = CalendarTimelineEvent(
    id: "overnight", title: "Late session", source: "lorvex", editable: true,
    startDate: "2026-05-22", startTime: "23:00", endDate: "2026-05-23", endTime: "01:00",
    allDay: false, location: nil, color: nil, eventType: "event",
    timezone: nil, isRecurring: false)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian); comps.timeZone = .current
  comps.year = 2026; comps.month = 5; comps.day = 23; comps.hour = 11; comps.minute = 0
  let newStart = try #require(comps.date)
  comps.hour = 12; comps.minute = 0
  let newEnd = try #require(comps.date)

  await store.rescheduleCalendarEvent(multiDay, newStart: newStart, newEnd: newEnd)
  // No-op: store leaves errorMessage alone and never calls update.
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func rescheduleCalendarEventSkipsRecurringEvents() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(), eventKitCoordinator: makeCoordinator())
  await store.refresh()
  let recurring = CalendarTimelineEvent(
    id: "weekly-standup", title: "Standup", source: "lorvex", editable: true,
    startDate: "2026-05-22", startTime: "09:00", endDate: nil, endTime: "09:30",
    allDay: false, location: nil, color: nil, eventType: "event",
    timezone: nil, isRecurring: true)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian); comps.timeZone = .current
  comps.year = 2026; comps.month = 5; comps.day = 22; comps.hour = 11; comps.minute = 0
  let newStart = try #require(comps.date)
  comps.hour = 11; comps.minute = 30
  let newEnd = try #require(comps.date)

  await store.rescheduleCalendarEvent(recurring, newStart: newStart, newEnd: newEnd)
  // Recurring drag-edits route through the sheet (this-instance vs series).
  #expect(store.errorMessage == nil)
}
