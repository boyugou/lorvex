import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import Testing

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMobile

/// FIX 3 (privacy): the EventKit ingest reads the effective calendar AI-access
/// tier from the core's persisted device-state, so a core-side downgrade that
/// purges the mirror is not silently re-mirrored at full detail on the next
/// calendar refresh — the reduced tier holds across refreshes.
@Suite struct EventKitTierPersistenceTests {

  private func makeOnDiskCore() -> (core: SwiftLorvexCoreService, cleanup: () -> Void) {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-tier-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("db.sqlite").path
    return (
      SwiftLorvexCoreService(databasePath: path),
      { try? FileManager.default.removeItem(at: dir) }
    )
  }

  /// Corrupt the persisted `calendar_ai_access_mode` so a subsequent read
  /// throws: `DeviceStateRepo` surfaces an unrecognized stored value as a
  /// validation error, standing in for on-disk corruption of the privacy
  /// control (the fail-safe path the ingest helpers must handle).
  private func corruptStoredTier(_ core: SwiftLorvexCoreService) throws {
    try core.write { db in
      try db.execute(
        sql: "INSERT OR REPLACE INTO device_state (key, value) VALUES (?, ?)",
        arguments: [PreferenceKeys.devCalendarAiAccessMode, "\"garbage\""])
    }
  }

  private static func date(_ ymd: String) -> Date {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: ymd)!
  }

  /// The stick-test: full-detail ingest → downgrade (purges) → re-ingest must
  /// mirror busy-only, because the coordinator reads the now-effective tier from
  /// the core through the production `effectiveCalendarAiAccessMode` helper.
  @MainActor
  @Test
  func macEventKitIngestHonorsPersistedTierDowngradeAcrossRefreshes() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }
    let access = FakeEventKitAccess(fetchResult: [
      EventKitFetchedEvent(
        key: "ek-board", title: "Board meeting", notes: "confidential",
        startDate: "2026-06-02", startTime: "10:00", endDate: "2026-06-02", endTime: "11:00",
        allDay: false, location: "HQ", timezone: "America/Los_Angeles",
        organizerEmail: "chair@example.com",
        attendees: [EventKitFetchedAttendee(email: "chair@example.com", status: .accepted)])
    ])
    // The coordinator reads its tier through the exact production wiring helper.
    let coordinator = EventKitCoordinator(
      access: access,
      provider: core,
      loadAccessMode: { await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core) },
      isEnabled: { true })

    let from = Self.date("2026-05-15")
    let to = Self.date("2026-06-20")

    // 1. Opt into full detail, then ingest — the real title + attendees mirror.
    _ = try await core.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.fullDetails.asString)
    _ = try await coordinator.ingest(from: from, to: to)
    var timeline = try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    var provider = try #require(timeline.events.first { $0.source == "provider" })
    #expect(provider.title == "Board meeting")
    #expect(provider.attendees?.isEmpty == false)

    // 2. Downgrade to busy-only. setPreference purges the full-detail mirror.
    _ = try await core.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)

    // 3. The next refresh re-ingests. Because the coordinator reads the
    //    now-busy tier from the core, the re-mirrored row is busy-only — the
    //    tier holds instead of being re-mirrored verbatim at full detail.
    _ = try await coordinator.ingest(from: from, to: to)
    timeline = try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    provider = try #require(timeline.events.first { $0.source == "provider" })
    #expect(provider.title == "Busy")
    #expect(provider.attendees == nil)
    #expect(provider.notes == nil)
  }

  /// FIX 1 (privacy): a non-tier-expressing calendar action — the enable toggle,
  /// a filter tweak, or the "Ingest Now" button, all of which funnel through
  /// `applyEventKitSettings(enabled:)` — must NOT force-rewrite the AI tier back
  /// to `full_details`. With `busy_only` stored, applying settings leaves the
  /// tier at `busy_only` and the re-ingest it drives stays busy-only (the
  /// re-mirrored provider row is redacted), instead of silently reverting the
  /// explicit downgrade and re-mirroring full detail.
  @MainActor
  @Test
  func macApplyEventKitSettingsPreservesExplicitBusyOnlyTier() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }

    // Persist an explicit Busy Only choice. A selection equal to the product
    // default is still stored so it remains a deliberate device-local choice.
    _ = try await core.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode,
      value: CalendarAiAccessMode.busyOnly.asString)

    let access = FakeEventKitAccess(fetchResult: [
      EventKitFetchedEvent(
        key: "ek-board", title: "Board meeting", notes: "confidential",
        startDate: "2026-06-02", startTime: "10:00", endDate: "2026-06-02", endTime: "11:00",
        allDay: false, location: "HQ", timezone: "America/Los_Angeles",
        organizerEmail: "chair@example.com",
        attendees: [EventKitFetchedAttendee(email: "chair@example.com", status: .accepted)])
    ])
    let coordinator = EventKitCoordinator(
      access: access,
      provider: core,
      loadAccessMode: { await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core) },
      isEnabled: { true })
    let store = AppStore(core: core, eventKitCoordinator: coordinator)

    // The non-tier action: enable/refresh via the settings-apply path.
    await store.applyEventKitSettings(enabled: true)

    // The explicit tier is untouched — not force-rewritten to full_details.
    #expect(
      try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
        == CalendarAiAccessMode.busyOnly.asString)

    // The re-ingest the apply drove stayed busy-only: the mirrored provider row
    // is redacted (no full-detail re-mirror).
    let timeline = try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-05")
    let provider = try #require(timeline.events.first { $0.source == "provider" })
    #expect(provider.title == "Busy")
    #expect(provider.attendees == nil)
    #expect(provider.notes == nil)
  }

  /// A device that has never chosen a tier resolves to Full Details, so the
  /// owner's own calendar mirrors verbatim without an opt-in step. Merely
  /// reading the mode (the launch/ingest behavior) must not materialize a
  /// device-state row, leaving the selection genuinely unset until the user
  /// picks one.
  @MainActor
  @Test
  func macMissingTierDefaultsToFullDetailsWithoutMaterializingRow() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }
    let mode = await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core)
    #expect(mode == CalendarAiAccessMode.defaultMode)
    #expect(mode == .fullDetails)
    let stored = try core.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT value FROM device_state WHERE key = ?",
        arguments: [PreferenceKeys.devCalendarAiAccessMode])
    }
    #expect(stored == nil)
  }

  /// `off` controls inbound provider visibility, not the independent macOS
  /// write-back half of the master EventKit integration. Settings must not hide
  /// Add to Calendar while the coordinator still permits write-back.
  @MainActor
  @Test
  func macOffTierKeepsMasterWriteBackEnabled() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }
    let coordinator = EventKitCoordinator(
      access: FakeEventKitAccess(),
      provider: core,
      loadAccessMode: { await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core) },
      isEnabled: { true })
    let store = AppStore(
      core: core,
      eventKitCoordinator: coordinator,
      eventKitIntegrationEnabled: false)

    let stored = await store.setCalendarAccessModeFromSettings(.off, enabled: true)

    #expect(stored)
    #expect(store.eventKitIntegrationEnabled)
    #expect(store.canAddTaskToCalendar)
    #expect(
      try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
        == CalendarAiAccessMode.off.asString)
  }

  /// macOS: a persisted tier that cannot be read must fail DOWN, not to maximum
  /// exposure. A corrupt row means the user's selection is unknown — distinct
  /// from an absent row, which resolves to the `full_details` default — so the
  /// ingest helper falls back to `busy_only`, never `full_details`.
  @MainActor
  @Test
  func macEffectiveTierFailsSafeDownWhenTierUnreadable() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }
    try corruptStoredTier(core)

    // Precondition: the corrupt row genuinely makes the read throw.
    var readThrew = false
    do {
      _ = try await core.getPreference(key: PreferenceKeys.devCalendarAiAccessMode)
    } catch {
      readThrew = true
    }
    #expect(readThrew)

    let mode = await LorvexAppleBootstrap.effectiveCalendarAiAccessMode(core: core)
    #expect(mode == CalendarAiAccessMode.failSafeMode)
    #expect(mode == .busyOnly)
    #expect(mode != .fullDetails)
  }

  /// iOS: the mobile ingest helper falls back to `busy_only` — not the
  /// `full_details` default — when the persisted tier is unreadable.
  @MainActor
  @Test
  func mobileEffectiveTierFailsSafeDownWhenTierUnreadable() async throws {
    let (core, cleanup) = makeOnDiskCore()
    defer { cleanup() }
    try corruptStoredTier(core)

    let store = MobileStore(core: core)
    let mode = await store.effectiveCalendarAiAccessMode()
    #expect(mode == CalendarAiAccessMode.failSafeMode)
    #expect(mode == .busyOnly)
    #expect(mode != .fullDetails)
  }
}
