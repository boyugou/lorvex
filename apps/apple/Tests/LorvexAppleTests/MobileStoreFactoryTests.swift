import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexMobile

@Suite("MobileStoreFactory")
@MainActor
struct MobileStoreFactoryTests {
  @Test("factory forwards runtime environment and selected tab")
  func factoryForwardsRuntimeEnvironment() async throws {
    let service = try await makeSeededInMemoryCore()
    let environment = [
      LorvexCoreRuntimeFactory.databasePathEnvironmentKey: "/tmp/mobile-runtime.db",
    ]
    // Inject ephemeral preferences so the factory resolves CloudSync to `.off`
    // (a real CKContainer traps in the unentitled test host) and the test does
    // not read or depend on the shared `UserDefaults.standard` domain.
    let suiteName = "test.mobile.factory.\(UUID().uuidString)"
    let preferenceDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { preferenceDefaults.removePersistentDomain(forName: suiteName) }
    var receivedEnvironment: [String: String] = [:]
    let factory = MobileStoreFactory(
      environment: environment,
      coreFactory: {
        receivedEnvironment = $0
        return service
      },
      widgetSnapshotPublisherFactory: { _ in NoopMobileWidgetSnapshotPublisher() },
      setupPreferencesFactory: { MobileSetupPreferences(defaults: preferenceDefaults) },
      todayString: { "2026-05-23" }
    )

    let store = factory.makeStore(selectedTab: .tasks)
    await store.refresh()

    #expect(receivedEnvironment == environment)
    #expect(store.selectedTab == .tasks)
    #expect(store.snapshot.today.tasks.isEmpty == false)
  }

  @Test("factory injects platform services")
  func factoryInjectsPlatformServices() async throws {
    let badgeCounter = FactoryBadgeCounter()
    let feedbackProvider = FactoryRecordingFeedbackProvider()
    let seededCore = try await makeSeededInMemoryCore()
    let factory = MobileStoreFactory(
      coreFactory: { _ in seededCore },
      feedbackProviderFactory: { feedbackProvider },
      setBadge: { await badgeCounter.set($0) }
    )

    let store = factory.makeStore()

    #expect(store.feedbackProvider is FactoryRecordingFeedbackProvider)
    await store.setBadge(7)
    #expect(await badgeCounter.value == 7)
  }

  @Test("factory injects mobile widget snapshot publisher")
  func factoryInjectsWidgetSnapshotPublisher() async throws {
    let publisher = FactoryRecordingMobileWidgetSnapshotPublisher()
    let seededCore = try await makeSeededInMemoryCore()
    let factory = MobileStoreFactory(
      coreFactory: { _ in seededCore },
      widgetSnapshotPublisherFactory: { _ in publisher }
    )

    let store = factory.makeStore()

    #expect(store.widgetSnapshotPublisher is FactoryRecordingMobileWidgetSnapshotPublisher)
  }

  @Test("refresh publishes mobile widget snapshot after loading planning surfaces")
  func refreshPublishesMobileWidgetSnapshot() async throws {
    let publisher = FactoryRecordingMobileWidgetSnapshotPublisher()
    let store = MobileStore(
      core: try await makeSeededInMemoryCore(),
      widgetSnapshotPublisher: publisher,
      todayString: { "2026-05-23" }
    )

    await store.refresh()

    let publication = try #require(await publisher.publications.first)
    #expect(publication.today.tasks.isEmpty == false)
    #expect(publication.today.tasks.count == store.snapshot.today.tasks.count)
    #expect(publication.lists?.lists.isEmpty == false)
  }

  @Test("default iOS factory mirrors mobile widget snapshots to the watch")
  func defaultIOSFactoryMirrorsSnapshotsToWatch() throws {
    let source = try String(
      contentsOf: applePackageRoot()
        .appending(path: "Sources/LorvexMobile/MobileStoreFactory.swift"),
      encoding: .utf8
    )

    #expect(source.contains("#if os(iOS)"))
    // The engine mirror seam forwards the projected snapshot value to the paired
    // watch's transport, replacing the former WatchMirroring* decorator.
    #expect(source.contains("configuredFromEnvironment(mirror: mirror)"))
    #expect(source.contains("WatchSnapshotReplicaMirror("))
    #expect(source.contains("core as? any LorvexWatchCommandServicing"))
    #expect(source.contains("commandService: commandService"))
  }

  @Test("Watch mirror binds its bounded projection to the producing Core workspace")
  func watchMirrorCarriesWorkspaceBaseline() async throws {
    let service = try await makeSeededInMemoryCore()
    let transport = FactoryRecordingWatchReplicaPublisher()
    let mirror = WatchSnapshotReplicaMirror(
      commandService: service,
      publisher: transport)
    let workspaceInstanceID = try await service.currentWatchWorkspaceInstanceID()
    let snapshot = watchSnapshotFixture(workspaceInstanceID: workspaceInstanceID)

    await mirror.publish(snapshot: snapshot)

    let envelope = try #require(transport.lastEnvelope)
    #expect(
      envelope.workspaceInstanceID
        == (try await service.currentWatchWorkspaceInstanceID()))
    let mirrored = try JSONDecoder().decode(WidgetSnapshot.self, from: envelope.snapshotData)
    #expect(mirrored.stats == snapshot.stats)
    #expect(mirrored.briefing == snapshot.briefing)
    #expect(mirrored.focusTasks == snapshot.focusTasks)
    #expect(mirrored.habits == snapshot.habits)
    #expect(mirrored.todayTasks.isEmpty)
    #expect(mirrored.lists.isEmpty)
    #expect(mirrored.listStats.isEmpty)
  }

  @Test("maximal source data projects to a valid bounded Watch snapshot")
  func watchProjectionAlwaysFitsReplicaEnvelope() throws {
    let longText = String(repeating: "🧭", count: 200)
    let focusTasks = (0..<40).map { index in
      WidgetSnapshot.FocusTask(
        id: snapshotIdentifier(index),
        title: longText,
        status: "open",
        dueDate: "2026-07-16",
        priority: index % 4,
        listID: snapshotIdentifier(index + 1_000),
        estimatedMinutes: 60)
    }
    let habits = (0..<200).map { index in
      WidgetSnapshot.HabitSummary(
        id: snapshotIdentifier(index + 2_000),
        name: longText,
        icon: String(repeating: "circle.fill", count: 20),
        completedToday: index % 3,
        target: 3)
    }
    let todayTasks = (0..<200).map { index in
      WidgetSnapshot.TodayTask(
        id: snapshotIdentifier(index + 3_000),
        title: longText,
        dueDate: "2026-07-16",
        priority: index % 4,
        estimatedMinutes: 60,
        listID: snapshotIdentifier(index + 4_000))
    }
    let lists = (0..<200).map { index in
      WidgetSnapshot.ListSummary(
        id: snapshotIdentifier(index + 4_000), name: longText, icon: "list.bullet")
    }
    let stats = WidgetSnapshot.Stats(
      focusCount: 40, overdueCount: 20, dueTodayCount: 30,
      attentionCount: 50, completedTodayCount: 10)
    let source = WidgetSnapshot(
      generatedAt: "2026-07-16T12:00:00Z",
      timezone: "America/Los_Angeles",
      logicalDay: "2026-07-16",
      stats: stats,
      briefing: String(repeating: "b", count: 100_000),
      focusTasks: focusTasks,
      habits: habits,
      todayTasks: todayTasks,
      lists: lists,
      listStats: lists.map { WidgetSnapshot.ListStats(id: $0.id, stats: stats) })

    let data = try WatchReplicaSnapshotProjector().encodedSnapshot(from: source)
    let projected = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(data.count <= LorvexWatchReplicaEnvelope.maximumSnapshotBytes)
    #expect(
      projected.focusTasks.map(\.id)
        == Array(focusTasks.prefix(WatchReplicaSnapshotProjector.maximumFocusTasks)).map(\.id))
    #expect(projected.habits.count <= WatchReplicaSnapshotProjector.maximumVisibleHabits)
    #expect(projected.habits.map(\.id) == Array(habits.prefix(projected.habits.count)).map(\.id))
    #expect(projected.habits.allSatisfy { $0.icon == nil })
    #expect(projected.generatedAt == source.generatedAt)
    #expect(projected.timezone == source.timezone)
    #expect(projected.logicalDay == source.logicalDay)
    #expect(
      projected.focusTasks.map(\.status)
        == Array(focusTasks.prefix(WatchReplicaSnapshotProjector.maximumFocusTasks)).map(\.status))
    #expect(
      projected.focusTasks.map(\.dueDate)
        == Array(focusTasks.prefix(WatchReplicaSnapshotProjector.maximumFocusTasks)).map(\.dueDate))
    #expect(projected.focusTasks.allSatisfy { $0.listID == nil })
    #expect(projected.stats == stats)
    #expect(projected.briefing?.utf8.count ?? 0 <= WatchReplicaSnapshotProjector.maximumBriefingUTF8Bytes)
    #expect(projected.todayTasks.isEmpty)
    #expect(projected.lists.isEmpty)
    #expect(projected.listStats.isEmpty)
  }

  @Test("Watch projection rejects rather than truncates a mutation identity")
  func watchProjectionFailsClosedForMalformedIdentity() throws {
    let valid = watchSnapshotFixture()
    let source = WidgetSnapshot(
      generatedAt: valid.generatedAt,
      timezone: valid.timezone,
      logicalDay: valid.logicalDay,
      stats: valid.stats,
      briefing: valid.briefing,
      focusTasks: [
        WidgetSnapshot.FocusTask(
          id: "00000000-0000-4000-8000-000000000001-extra",
          title: "Do not fabricate this entity",
          status: "open",
          dueDate: "2026-07-16",
          priority: 1,
          listID: nil,
          estimatedMinutes: 30)
      ],
      habits: [])

    #expect(
      throws: WatchReplicaSnapshotProjectionError.invalidSemanticField("focus_tasks.id")
    ) {
      try WatchReplicaSnapshotProjector().encodedSnapshot(from: source)
    }

    #expect(
      throws: WatchReplicaSnapshotProjectionError.invalidSemanticField("generated_at")
    ) {
      try WatchReplicaSnapshotProjector().encodedSnapshot(
        from: watchSnapshotFixture(generatedAt: "2026-07-16T12:00:00.000Z"))
    }
  }
}

private func applePackageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func snapshotIdentifier(_ value: Int) -> String {
  String(format: "00000000-0000-4000-8000-%012d", value)
}

private func watchSnapshotFixture(
  generatedAt: String = "2026-07-16T12:00:00Z",
  workspaceInstanceID: String = WidgetSnapshot.unscopedWorkspaceInstanceID
) -> WidgetSnapshot {
  WidgetSnapshot(
    generatedAt: generatedAt,
    workspaceInstanceID: workspaceInstanceID,
    timezone: "America/Los_Angeles",
    logicalDay: "2026-07-16",
    stats: .init(
      focusCount: 1, overdueCount: 0, dueTodayCount: 1, completedTodayCount: 2),
    briefing: "Ready.",
    focusTasks: [
      .init(
        id: snapshotIdentifier(1), title: "Review spec", status: "in_progress",
        dueDate: "2026-07-16", priority: 1, listID: nil, estimatedMinutes: 30)
    ],
    habits: [
      .init(
        id: snapshotIdentifier(2), name: "Exercise", icon: "figure.run",
        completedToday: 1, target: 2)
    ])
}

private actor FactoryBadgeCounter {
  private(set) var value: Int?
  func set(_ count: Int) { value = count }
}

private struct FactoryRecordingFeedbackProvider: LorvexFeedbackProviding {
  func playFeedback(_ kind: LorvexFeedbackKind) {}
}

@MainActor
private final class FactoryRecordingWatchReplicaPublisher: WatchReplicaPublishing {
  private(set) var envelopes: [LorvexWatchReplicaEnvelope] = []
  var lastEnvelope: LorvexWatchReplicaEnvelope? { envelopes.last }

  func publish(replicaEnvelope: LorvexWatchReplicaEnvelope) async {
    envelopes.append(replicaEnvelope)
  }
}

private final class FactoryRecordingMobileWidgetSnapshotPublisher: MobileWidgetSnapshotPublishing,
  @unchecked Sendable
{
  struct Publication: Sendable {
    var today: TodaySnapshot
    var currentFocus: CurrentFocusPlan?
    var habitCatalog: HabitCatalogSnapshot?
    var lists: ListCatalogSnapshot?
  }

  private let lock = NSLock()
  private var recordedPublications: [Publication] = []

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    lock.withLock {
      recordedPublications.append(
        Publication(
          today: source.today,
          currentFocus: source.currentFocus,
          habitCatalog: source.habits,
          lists: source.lists))
    }
    return WidgetSnapshotProjector().snapshot(
      storageGeneration: source.storageGeneration,
      logicalDay: source.logicalDay,
      today: source.today,
      currentFocus: source.currentFocus,
      timezone: "UTC",
      habitCatalog: source.habits,
      listCatalog: source.lists,
      statsSource: source.stats)
  }

  func publish(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    habitCatalog: HabitCatalogSnapshot?,
    lists: ListCatalogSnapshot?
  ) async throws -> WidgetSnapshot {
    lock.withLock {
      recordedPublications.append(
        Publication(
          today: today,
          currentFocus: currentFocus,
          habitCatalog: habitCatalog,
          lists: lists
        )
      )
    }
    return WidgetSnapshotProjector().snapshot(
      today: today,
      currentFocus: currentFocus,
      timezone: "UTC",
      habitCatalog: habitCatalog,
      listCatalog: lists
    )
  }

  var publications: [Publication] {
    get async { lock.withLock { recordedPublications } }
  }
}
