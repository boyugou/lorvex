import Foundation
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMobile
@testable import LorvexSystemIntents

/// The `status × surface-projection` matrix: for each lifecycle status, assert
/// its presence/absence in every app-layer projection a started task must reach.
/// This is the regression net for the cross-surface `in_progress` gap — a
/// started task has to behave like actionable work everywhere `open` does, and
/// this suite fails if any surface reverts to an exact-`.open` filter.
///
/// | status       | actionable | active | reminder | badge/widget | workspace open lane | batch-cancel(id) |
/// |--------------|:---------: |:------:|:--------:|:------------:|:-------------------:|:----------------:|
/// | open         |     ✓      |   ✓    |    ✓     |      ✓       |         ✓           |     cancelled    |
/// | in_progress  |     ✓      |   ✓    |    ✓     |      ✓       |         ✓           |     cancelled    |
/// | someday      |     ✗      |   ✓    |    ✗     |      ✗       |         ✗           |     cancelled    |
/// | completed    |     ✗      |   ✗    |    ✗     |      ✗       |         ✗           |     skipped      |
/// | cancelled    |     ✗      |   ✗    |    ✗     |      ✗       |         ✗           |     skipped      |
@Suite("in_progress surface matrix")
struct InProgressSurfaceMatrixTests {
  private static let allStatuses: [LorvexTask.Status] =
    [.open, .inProgress, .someday, .completed, .cancelled]
  private static let actionable: Set<LorvexTask.Status> = [.open, .inProgress]
  private static let active: Set<LorvexTask.Status> = [.open, .inProgress, .someday]

  // MARK: - Shared classification policy (the single source of truth)

  @Test("isActionable and isActive match the matrix for every status")
  func classificationMatrix() {
    for status in Self.allStatuses {
      #expect(status.isActionable == Self.actionable.contains(status), "isActionable \(status)")
      #expect(status.isActive == Self.active.contains(status), "isActive \(status)")
    }
  }

  @Test("app-layer status delegates classification to the domain status")
  func appStatusDelegatesToDomain() {
    for status in Self.allStatuses {
      #expect(status.isActionable == status.domainStatus.isActionable)
      #expect(status.isActive == status.domainStatus.isActive)
      #expect(status.isResolved == status.domainStatus.isTerminal)
    }
  }

  // MARK: - Tasks-workspace open lane (macOS + iPhone)

  @Test("macOS + iPhone workspace open lane query the actionable working set")
  func workspaceOpenLaneRoutesActionable() {
    #expect(TaskWorkspaceSection.open.coreStatusRawValue == LorvexTask.Status.actionableFilter)
    #expect(MobileTaskWorkspaceStatus.open.coreStatus == LorvexTask.Status.actionableFilter)
    // Non-open lanes still bind their exact status.
    #expect(TaskWorkspaceSection.someday.coreStatusRawValue == "someday")
    #expect(TaskWorkspaceSection.completed.coreStatusRawValue == "completed")
    #expect(MobileTaskWorkspaceStatus.completed.coreStatus == "completed")
  }

  @Test("iPhone open lane membership includes started, excludes parked/terminal")
  func mobileOpenLaneIncludesMatrix() {
    for status in Self.allStatuses {
      let task = Self.task(status: status)
      #expect(
        MobileTaskWorkspaceStatus.open.includes(task) == Self.actionable.contains(status),
        "open lane includes \(status)")
    }
    // The someday lane still admits only someday.
    #expect(MobileTaskWorkspaceStatus.someday.includes(Self.task(status: .someday)))
    #expect(!MobileTaskWorkspaceStatus.someday.includes(Self.task(status: .inProgress)))
  }

  // MARK: - Reminders (macOS + iPhone both filter isActionable)

  @Test("reminder eligibility is the actionable set — a started task keeps reminders")
  func reminderEligibilityIsActionable() {
    for status in Self.allStatuses {
      // Both AppStoreAppleSurfacePublishing (macOS) and MobileStoreNotificationActions
      // (iPhone) arm reminders for exactly `status.isActionable`.
      #expect(Self.task(status: status).status.isActionable == Self.actionable.contains(status))
    }
  }

  // MARK: - Badge + widget snapshot

  @Test("badge counts actionable overdue/due-today work, including started tasks")
  func badgeCountsActionable() {
    // A fixed past due date so every task is overdue relative to `today`; only
    // the actionable (open + started) ones should be counted.
    let overdue = Date(timeIntervalSince1970: 0)
    let tasks = Self.allStatuses.map {
      makePublisherWidgetTask(
        id: "badge-\($0.rawValue)", title: $0.rawValue, priority: .p2,
        status: $0, dueDate: overdue, estimatedMinutes: nil)
    }
    #expect(
      BadgeCoordinator.badgeCount(tasks: tasks, today: "2026-07-13") == Self.actionable.count)
  }

  @Test("widget snapshot surfaces started tasks and drops parked/terminal")
  func widgetSnapshotIncludesStarted() {
    let tasks = Self.allStatuses.map {
      makePublisherWidgetTask(
        id: "wid-\($0.rawValue)", title: $0.rawValue, priority: .p2,
        status: $0, dueDate: nil, estimatedMinutes: nil)
    }
    let snapshot = TodaySnapshot(
      focusTitle: "Today", summary: "", tasks: tasks, localChangeSequence: 0)
    let projector = WidgetSnapshotProjector(maxFocusTasks: 6)
    let widget = projector.snapshot(today: snapshot, currentFocus: nil, timezone: nil)
    let ids = Set(widget.focusTasks.map(\.id))
    #expect(ids == ["wid-open", "wid-in_progress"], "widget focus = actionable only")

    // Pin the downstream consumer too: projection already contained a started
    // task while `WidgetRenderModelBuilder` once applied a second exact-`open`
    // filter and silently removed it from the rendered widget/watch payload.
    let model = WidgetRenderModelBuilder().model(
      entry: .init(
        date: Date(),
        state: .snapshot(widget, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: Date()
      ),
      family: .systemLarge,
      statusText: "Updated now"
    )
    #expect(
      Set(model.taskRows.map(\.id)) == ["wid-open", "wid-in_progress"],
      "rendered widget focus = actionable only"
    )
  }

  // MARK: - Open/deferred sections keep in_progress out (shown in its own section)

  @Test("open & deferred display sections exclude started tasks (own section)")
  func displaySectionsExcludeStarted() {
    let openNoPlan = Self.task(id: "o", status: .open)
    var openPlanned = Self.task(id: "d", status: .open)
    openPlanned.plannedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let started = Self.task(id: "w", status: .inProgress)
    let pool = [openNoPlan, openPlanned, started]
    #expect(pool.lorvexOpenSection.map(\.id) == ["o"])
    #expect(pool.lorvexDeferredSection.map(\.id) == ["d"])
  }

  // MARK: - App-Intents status picker

  @Test("App-Intents status picker carries in_progress with a localized label")
  func appIntentPickerHasInProgress() {
    #expect(LorvexTaskStatusOption(rawValue: "in_progress") == .inProgress)
    #expect(LorvexTaskStatusOption.caseDisplayRepresentations[.inProgress] != nil)
    // The raw-status label resolver returns a mapped title, not the raw fallback.
    let label = LorvexTaskStatusOption.localizedLabel(forRawStatus: "in_progress")
    #expect(String(localized: label) == "In Progress")
  }

  // MARK: - Store-backed projections (real in-memory core)

  @Test("actionable list query surfaces a started task; open lane stays distinct")
  func actionableQuerySurfacesStarted() async throws {
    let service = try makeInMemoryCore()
    var ids: [LorvexTask.Status: String] = [:]
    for status in Self.allStatuses {
      ids[status] = try await Self.makeTask(service, status: status, title: status.rawValue)
    }
    let actionable = try await service.listTasks(
      status: LorvexTask.Status.actionableFilter, listID: nil, priority: nil,
      text: nil, limit: 50, offset: 0)
    let actionableIDs = Set(actionable.tasks.map(\.id))
    for status in Self.allStatuses {
      #expect(
        actionableIDs.contains(ids[status]!) == Self.actionable.contains(status),
        "actionable query contains \(status)")
    }
    // The plain `open` lane still excludes a started task (they are distinct).
    let openLane = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
    #expect(!openLane.tasks.map(\.id).contains(ids[.inProgress]!))
  }

  @Test("App-Intent suggested entities are the active set (started included)")
  func appIntentEntityQueryIsActive() async throws {
    let service = try makeInMemoryCore()
    var ids: [LorvexTask.Status: String] = [:]
    for status in Self.allStatuses {
      ids[status] = try await Self.makeTask(service, status: status, title: status.rawValue)
    }
    let entities = try await LorvexTaskEntityQuery.suggestedEntities(core: service)
    let entityIDs = Set(entities.map(\.id))
    for status in Self.allStatuses {
      #expect(
        entityIDs.contains(ids[status]!) == Self.active.contains(status),
        "App-Intent entities contain \(status)")
    }
  }

  @Test("batch_cancel_tasks(ids) cancels a started task, skips only terminal")
  func batchCancelByIdCancelsStarted() async throws {
    let service = try makeInMemoryCore()
    var ids: [LorvexTask.Status: String] = [:]
    for status in Self.allStatuses {
      ids[status] = try await Self.makeTask(service, status: status, title: status.rawValue)
    }
    let result = try await service.batchCancelTasks(
      ids: Self.allStatuses.map { ids[$0]! }, cancelSeries: false)
    let cancelled = Set(result.cancelled.map(\.id))
    let skipped = Set(result.skipped)
    #expect(cancelled.contains(ids[.open]!))
    #expect(
      cancelled.contains(ids[.inProgress]!), "an explicit id cancel applies to a started task")
    #expect(cancelled.contains(ids[.someday]!))
    #expect(skipped == [ids[.completed]!, ids[.cancelled]!], "only terminal tasks skip")
  }

  // MARK: - Today "In Progress" section — the >10 boundary

  @Test("Today in-progress section reads ALL started tasks past the 10-cap overview")
  func todayInProgressSectionUncappedBeyondCap() async throws {
    let service = try makeInMemoryCore()
    var startedIDs: Set<String> = []
    // 12 started tasks — more than the 10-task overview cap — plus a few plain
    // open tasks so the capped `tasks` pool is genuinely full.
    for i in 0..<12 {
      let id = try await Self.makeTask(service, status: .inProgress, title: "wip-\(i)")
      startedIDs.insert(id)
    }
    for i in 0..<4 {
      _ = try await Self.makeTask(service, status: .open, title: "open-\(i)")
    }

    let today = try await service.loadToday()
    #expect(today.tasks.count <= 10, "overview pool stays priority-capped")
    #expect(
      today.inProgressTasks.count == 12,
      "in-progress section is uncapped — all 12 started tasks, not a slice of the cap")
    #expect(Set(today.inProgressTasks.map(\.id)) == startedIDs)

    // The iPhone Today "In Progress" section reads the same uncapped field.
    let snapshot = MobileHomeSnapshot(today: today, currentFocus: nil, weeklyReview: nil)
    #expect(Set(snapshot.inProgressTasks.map(\.id)) == startedIDs)
    #expect(
      !MobileTodayTaskSections.showsOpenTaskEmptyState(for: snapshot),
      "a started-only Today must not claim that the user needs to get started")
  }

  @Test("Today capture empty state appears only when both open and started work are absent")
  func todayEmptyStateExcludesInProgressOnlySnapshot() {
    let empty = MobileHomeSnapshot(today: .empty, currentFocus: nil, weeklyReview: nil)
    #expect(MobileTodayTaskSections.showsOpenTaskEmptyState(for: empty))

    let startedToday = TodaySnapshot(
      focusTitle: "Today", summary: "", tasks: [],
      inProgressTasks: [Self.task(status: .inProgress)], localChangeSequence: 0)
    let started = MobileHomeSnapshot(
      today: startedToday, currentFocus: nil, weeklyReview: nil)
    #expect(!MobileTodayTaskSections.showsOpenTaskEmptyState(for: started))

    let openToday = TodaySnapshot(
      focusTitle: "Today", summary: "", tasks: [Self.task(status: .open)],
      localChangeSequence: 0)
    let open = MobileHomeSnapshot(today: openToday, currentFocus: nil, weeklyReview: nil)
    #expect(!MobileTodayTaskSections.showsOpenTaskEmptyState(for: open))
  }

  @MainActor
  @Test("mobile task resolution and cache updates include the uncapped in-progress pool")
  func mobileTaskResolutionIncludesInProgressPool() async throws {
    let service = try makeInMemoryCore()
    let id = try await Self.makeTask(service, status: .inProgress, title: "mobile-wip")
    let today = try await service.loadToday()
    let store = MobileStore(core: service)
    store.snapshot = MobileHomeSnapshot(today: today, currentFocus: nil, weeklyReview: nil)

    #expect(store.resolveTask(id)?.status == .inProgress)
    #expect(store.allKnownTasks.contains { $0.id == id })

    var updated = try #require(store.resolveTask(id))
    updated.title = "updated in-progress title"
    store.replaceKnownTask(updated)
    #expect(store.snapshot.inProgressTasks.first { $0.id == id }?.title == updated.title)
  }

  // MARK: - Fixtures

  private static func task(id: String = "t", status: LorvexTask.Status) -> LorvexTask {
    LorvexTask(
      id: id, title: id, notes: "", priority: .p2, status: status,
      dueDate: nil, estimatedMinutes: nil, tags: [])
  }

  private static func makeTask(
    _ service: SwiftLorvexCoreService, status: LorvexTask.Status, title: String
  ) async throws -> String {
    let created = try await service.createTask(title: title, notes: "")
    switch status {
    case .open: break
    case .inProgress: _ = try await service.startTask(id: created.id)
    case .someday: _ = try await service.markTaskSomeday(id: created.id)
    case .completed: _ = try await service.completeTask(id: created.id)
    case .cancelled: _ = try await service.cancelTask(id: created.id)
    }
    return created.id
  }
}
