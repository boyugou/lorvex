import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexMobile

actor FakeMobileSettingsEventKitCoordinator: MobileEventKitCoordinating {
  var availableCalendarsResult: [EventKitCalendarDescriptor] = []
  var availableCalendarsError: Error?
  private(set) var requestAccessCallCount = 0
  private(set) var ingestCallCount = 0
  private(set) var lastIngestAccessMode: CalendarAiAccessMode?
  private(set) var lastIngestWindow: (start: String, end: String)?
  private(set) var lastIngestRequestedAccess = false
  private let requestAccessResult: Bool
  private let shouldBlockRequestAccess: Bool
  private let shouldBlockFirstIngest: Bool
  private var requestAccessStartedContinuation: CheckedContinuation<Void, Never>?
  private var releaseRequestAccessContinuation: CheckedContinuation<Void, Never>?
  private var firstIngestStartedContinuation: CheckedContinuation<Void, Never>?
  private var releaseFirstIngestContinuation: CheckedContinuation<Void, Never>?

  init(
    requestAccessResult: Bool = true,
    shouldBlockRequestAccess: Bool = false,
    shouldBlockFirstIngest: Bool = false
  ) {
    self.requestAccessResult = requestAccessResult
    self.shouldBlockRequestAccess = shouldBlockRequestAccess
    self.shouldBlockFirstIngest = shouldBlockFirstIngest
  }

  func requestAccess() async throws -> Bool {
    requestAccessCallCount += 1
    requestAccessStartedContinuation?.resume()
    requestAccessStartedContinuation = nil
    if shouldBlockRequestAccess {
      await withCheckedContinuation { continuation in
        releaseRequestAccessContinuation = continuation
      }
    }
    return requestAccessResult
  }

  func availableCalendars(enabled: Bool) async throws -> [EventKitCalendarDescriptor] {
    guard enabled else { return [] }
    if let availableCalendarsError {
      throw availableCalendarsError
    }
    return availableCalendarsResult
  }

  func ingest(
    enabled: Bool,
    accessMode: CalendarAiAccessMode,
    calendarFilter: EventKitCalendarFilter,
    from: Date,
    to: Date,
    windowStart: String,
    windowEnd: String,
    requestAccess: Bool
  ) async throws -> Int {
    ingestCallCount += 1
    lastIngestAccessMode = accessMode
    lastIngestWindow = (windowStart, windowEnd)
    lastIngestRequestedAccess = requestAccess
    if shouldBlockFirstIngest, ingestCallCount == 1 {
      firstIngestStartedContinuation?.resume()
      firstIngestStartedContinuation = nil
      await withCheckedContinuation { continuation in
        releaseFirstIngestContinuation = continuation
      }
    }
    return 0
  }

  func waitForRequestAccessToStart() async {
    if requestAccessCallCount > 0 { return }
    await withCheckedContinuation { continuation in
      requestAccessStartedContinuation = continuation
    }
  }

  func releaseRequestAccess() {
    releaseRequestAccessContinuation?.resume()
    releaseRequestAccessContinuation = nil
  }

  func waitForFirstIngestToStart() async {
    if ingestCallCount > 0 { return }
    await withCheckedContinuation { continuation in
      firstIngestStartedContinuation = continuation
    }
  }

  func releaseFirstIngest() {
    releaseFirstIngestContinuation?.resume()
    releaseFirstIngestContinuation = nil
  }
}

@MainActor
@Test
func mobileCalendarFilterPersistsToSharedEventKitConfigKeys() async throws {
  let suiteName = "test.mobile.calendarFilter.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    defaults: defaults,
    eventKitCalendarFilterMode: .allExcept,
    eventKitExcludedCalendarIDs: ["personal"]
  )

  store.setEventKitCalendarFilterModeFromSettings(.onlySelected)
  store.setEventKitIncludedCalendarIDsFromSettings(["work", "family"])

  let restored = MobileSetupPreferences(defaults: defaults)
  #expect(restored.eventKitCalendarFilterMode == .onlySelected)
  #expect(restored.eventKitIncludedCalendarIDs == ["family", "work"])
  #expect(restored.eventKitExcludedCalendarIDs.isEmpty)
  #expect(
    restored.eventKitCalendarFilter
      == EventKitCalendarFilter(
        mode: .onlySelected,
        selectedCalendarIDs: ["family", "work"],
        excludedCalendarIDs: []
      )
  )
  #expect(defaults.string(forKey: "eventKitCalendarFilterMode") == "onlySelected")
  #expect(defaults.stringArray(forKey: "eventKitIncludedCalendarIDs") == ["family", "work"])
  #expect(defaults.stringArray(forKey: "eventKitExcludedCalendarIDs") == [])
}

@MainActor
@Test
func mobileEventKitDeniedAccessLeavesToggleOffAndShowsSettingsRecovery() async throws {
  let suiteName = "test.mobile.calendarDenied.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    defaults: defaults,
    eventKitCoordinator: FakeMobileSettingsEventKitCoordinator(requestAccessResult: false)
  )

  await store.setEventKitEnabledFromSettings(true)

  #expect(store.eventKitEnabled == false)
  #expect(MobileSetupPreferences(defaults: defaults).eventKitEnabled == false)
  #expect(store.eventKitSettingsRecoveryNeeded == true)
  #expect(store.lastEventKitImportErrorMessage?.contains("Calendar access is off") == true)
}

@MainActor
@Test
func mobileEventKitEnableSettingIgnoresSecondTapWhileRequestInFlight() async throws {
  let coordinator = FakeMobileSettingsEventKitCoordinator(shouldBlockRequestAccess: true)
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: coordinator
  )

  let first = Task { await store.setEventKitEnabledFromSettings(true) }
  await coordinator.waitForRequestAccessToStart()
  await store.setEventKitEnabledFromSettings(true)
  #expect(await coordinator.requestAccessCallCount == 1)

  await coordinator.releaseRequestAccess()
  await first.value

  #expect(store.eventKitEnabled == true)
  #expect(await coordinator.requestAccessCallCount == 1)
}

/// FIX 3 (privacy): the iOS incidental-refresh ingest must read the effective
/// calendar AI-access tier from the core's persisted device-state and pass it to
/// the coordinator, so a core-side downgrade (Settings / App Intents) is honored on
/// the next refresh rather than re-mirrored at a hardcoded full-detail tier.
@MainActor
@Test
func mobileEventKitIngestReadsPersistedTierFromCore() async throws {
  let core = try await makeSeededInMemoryCore()
  _ = try await core.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.busyOnly.asString)
  let coordinator = FakeMobileSettingsEventKitCoordinator()
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)

  await store.ingestEventKitWindow(fromDay: "2026-07-20", throughDay: "2026-07-20")

  #expect(await coordinator.ingestCallCount == 1)
  #expect(await coordinator.lastIngestAccessMode == .busyOnly)
  #expect(await coordinator.lastIngestWindow?.start == "2026-07-20")
  #expect(await coordinator.lastIngestWindow?.end == "2026-07-20")
}

/// FIX 1 (privacy): the iOS settings-apply path (`applyEventKitSettingsFromSettings`,
/// reached from the enable/disable toggle AND every calendar-filter tweak) must
/// NOT force-rewrite the AI tier to `full_details`. With `busy_only` stored, an
/// apply leaves the tier at `busy_only` and the ingest it drives uses the busy
/// tier — instead of silently reverting the explicit downgrade and re-mirroring
/// full detail on the next ingest.
@MainActor
@Test
func mobileApplyEventKitSettingsPreservesExplicitBusyOnlyTier() async throws {
  let core = try await makeSeededInMemoryCore()
  _ = try await core.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.busyOnly.asString)
  let coordinator = FakeMobileSettingsEventKitCoordinator()
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)

  await store.applyEventKitSettingsFromSettings(requestAccess: false)

  // The explicit tier is untouched — not force-rewritten to full_details.
  #expect(
    try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
      == CalendarAiAccessMode.busyOnly.asString)
  // The ingest the apply drove read the preserved busy tier, so nothing is
  // re-mirrored at full detail.
  #expect(await coordinator.ingestCallCount == 1)
  #expect(await coordinator.lastIngestAccessMode == .busyOnly)
}

/// A device with no stored tier starts at the domain's privacy-safe Busy Only
/// default. Applying settings must use that tier rather than silently pinning
/// Full Details on first enable.
@MainActor
@Test
func mobileMissingTierDefaultsToBusyOnlyOnSettingsApply() async throws {
  let core = try await makeSeededInMemoryCore()
  let coordinator = FakeMobileSettingsEventKitCoordinator()
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)

  #expect(await store.calendarAccessModeFromSettings() == .busyOnly)
  await store.applyEventKitSettingsFromSettings(requestAccess: false)

  #expect(await coordinator.ingestCallCount == 1)
  #expect(await coordinator.lastIngestAccessMode == .busyOnly)
  #expect(
    try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
      == CalendarAiAccessMode.busyOnly.asString)
}

/// Full Details is reachable only through an explicit Settings selection, which
/// persists in device_state and drives the immediate reconciliation ingest.
@MainActor
@Test
func mobileSettingsCanExplicitlySelectFullDetails() async throws {
  let core = try await makeSeededInMemoryCore()
  let coordinator = FakeMobileSettingsEventKitCoordinator()
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)

  let stored = await store.setCalendarAccessModeFromSettings(.fullDetails)

  #expect(stored)
  #expect(await coordinator.ingestCallCount == 1)
  #expect(await coordinator.lastIngestAccessMode == .fullDetails)
  #expect(
    try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
      == CalendarAiAccessMode.fullDetails.asString)
}

/// A privacy-tier change can land while an older EventKit projection is waiting
/// in the OS actor. The settings apply flight must run one trailing pass and the
/// tier setter must not return until that final pass has observed the downgrade.
@MainActor
@Test
func mobileEventKitSettingsApplyRerunsAfterConcurrentPrivacyDowngrade() async throws {
  let core = try await makeSeededInMemoryCore()
  _ = try await core.setPreference(
    key: PreferenceKeys.devCalendarAiAccessMode,
    value: CalendarAiAccessMode.fullDetails.asString)
  let coordinator = FakeMobileSettingsEventKitCoordinator(shouldBlockFirstIngest: true)
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)

  let initialApply = Task {
    await store.applyEventKitSettingsFromSettings(requestAccess: false)
  }
  await coordinator.waitForFirstIngestToStart()

  let downgrade = Task { await store.setCalendarAccessModeFromSettings(.off) }
  await Task.yield()
  #expect(await coordinator.ingestCallCount == 1)

  await coordinator.releaseFirstIngest()
  await initialApply.value
  #expect(await downgrade.value)

  #expect(await coordinator.ingestCallCount == 2)
  #expect(await coordinator.lastIngestAccessMode == .off)
  #expect(!store.eventKitSettingsApplyFlight.isRunning)
  #expect(!store.eventKitSettingsApplyFlight.isPendingRerun)
}

@MainActor
@Test("EventKit settings reconcile the exact visible window and forward access requests")
func mobileEventKitSettingsApplyPreservesVisibleWindow() async throws {
  let core = try await makeSeededInMemoryCore()
  let coordinator = FakeMobileSettingsEventKitCoordinator()
  let store = MobileStore(core: core, eventKitCoordinator: coordinator, eventKitEnabled: true)
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-05-01", to: "2026-05-31", events: [], truncated: false, nextOffset: nil)

  await store.applyEventKitSettingsFromSettings(requestAccess: true)

  #expect(await coordinator.lastIngestWindow?.start == "2026-05-01")
  #expect(await coordinator.lastIngestWindow?.end == "2026-05-31")
  #expect(await coordinator.lastIngestRequestedAccess)
  #expect(store.calendarTimeline?.from == "2026-05-01")
  #expect(store.calendarTimeline?.to == "2026-05-31")
}

@MainActor
@Test
func mobileEventKitSettingsApplyRefreshesDiagnostics() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(
    core: core,
    eventKitCoordinator: FakeMobileSettingsEventKitCoordinator(),
    eventKitEnabled: true
  )

  await store.applyEventKitSettingsFromSettings(requestAccess: false)

  #expect(core.loadRuntimeDiagnosticsCallCount == 1)
}
