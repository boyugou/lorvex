@preconcurrency import CloudKit
import Foundation
import LorvexCloudSync
import LorvexCore

public enum MobileCloudSyncLifecycleResult: Equatable, Sendable {
  case newData
  case noData
  case failed

  /// Fold coalesced cycle passes without losing evidence that any pass made
  /// data available. A successful data-bearing pass dominates a failure; a
  /// failure dominates a run of no-op passes.
  static func combine(
    _ accumulated: MobileCloudSyncLifecycleResult,
    _ next: MobileCloudSyncLifecycleResult
  ) -> MobileCloudSyncLifecycleResult {
    if accumulated == .newData || next == .newData { return .newData }
    if accumulated == .failed || next == .failed { return .failed }
    return .noData
  }
}

/// Internal result carried by the cycle single-flight. The lifecycle value is
/// not enough on its own: post-cycle fan-out also needs the union of every
/// pass's applied entity kinds. Without retaining the aggregate report, a
/// trailing no-op pass could overwrite a data-bearing first pass and leave the
/// UI stale even though the coalesced lifecycle result was `.newData`.
struct MobileCloudSyncCycleOutcome: Sendable {
  var lifecycle: MobileCloudSyncLifecycleResult
  var report: CloudSyncCycleReport?

  static func combine(
    _ accumulated: MobileCloudSyncCycleOutcome,
    _ next: MobileCloudSyncCycleOutcome
  ) -> MobileCloudSyncCycleOutcome {
    MobileCloudSyncCycleOutcome(
      lifecycle: MobileCloudSyncLifecycleResult.combine(
        accumulated.lifecycle, next.lifecycle),
      report: combineReports(accumulated.report, next.report))
  }

  private static func combineReports(
    _ accumulated: CloudSyncCycleReport?,
    _ next: CloudSyncCycleReport?
  ) -> CloudSyncCycleReport? {
    guard var aggregate = accumulated else { return next }
    guard let next else { return aggregate }
    aggregate.accumulate(next)
    return aggregate
  }
}

struct MobileCloudSyncModeRequest: Sendable {
  fileprivate let mode: CloudSyncMode
  fileprivate let deletionEpoch: UInt64
}

extension MobileStore {
  func makeCloudSyncModeRequest(_ mode: CloudSyncMode) -> MobileCloudSyncModeRequest {
    MobileCloudSyncModeRequest(mode: mode, deletionEpoch: cloudDataDeletionEpoch)
  }

  public func setCloudSyncModeFromSettings(_ mode: CloudSyncMode) async {
    await setCloudSyncModeFromSettings(makeCloudSyncModeRequest(mode))
  }

  /// Switches sync on or off in the running app. The mode changes before the
  /// first suspension, so the picker never snaps back. Turning sync on lifts a
  /// standing cloud-data deletion pause (turning sync on is that consent),
  /// starts the controller, then runs a full refresh whose pass uploads the
  /// local database; turning it off stops the controller and keeps local data,
  /// the outbox, and the engine state for a later resume.
  ///
  /// The UI creates `request` synchronously in the Binding setter, before
  /// spawning its Task, so a deletion accepted meanwhile voids it and delayed
  /// task scheduling cannot resurrect deleted cloud data.
  func setCloudSyncModeFromSettings(_ request: MobileCloudSyncModeRequest) async {
    guard request.deletionEpoch == cloudDataDeletionEpoch, !isCloudDataDeletionRunning,
      cloudSyncMode != request.mode
    else { return }
    MobileSetupPreferences(defaults: defaults).setCloudSyncMode(request.mode)
    cloudSyncMode = request.mode
    if let cloudSyncController {
      if request.mode == .live {
        isSettingCloudSyncMode = true
        await liftCloudDeletionPauseForExplicitReenable(deletionEpoch: request.deletionEpoch)
        await applyCloudSyncControllerState(await cloudSyncController.start())
        isSettingCloudSyncMode = false
        // The first pass can upload the whole database; it reports its own
        // progress through the status fields instead of holding the picker.
        Task { await self.refresh() }
      } else {
        await cloudSyncController.stop()
      }
    }
    await loadRuntimeDiagnostics()
  }

  /// Starts the app-lifetime observers once and retains them on the store,
  /// which outlives every view. They keep running across navigation instead of
  /// being cancelled with a per-view `.task`.
  public func startLifetimeObserversIfNeeded() {
    guard lifetimeObserverTasks.isEmpty else { return }
    DatabaseChangeSignal.startObserving()
    lifetimeObserverTasks = [
      Task { [weak self] in await self?.connectCloudSyncReports() },
      Task { [weak self] in await self?.observeSyncRequests() },
      Task { [weak self] in await self?.observeCloudKitAccountChanges() },
      Task { [weak self] in await self?.observeDatabaseChangeSignal() },
      Task { [weak self] in await self?.observeBackgroundMutationsApplied() },
      Task { [weak self] in await self?.observeNotificationActionErrors() },
      Task { [weak self] in await self?.observeCalendarDayChange() },
    ]
    rescheduleLogicalDayBoundaryWake()
    #if canImport(EventKit)
      if eventKitCoordinator != nil {
        lifetimeObserverTasks.append(
          Task { [weak self] in await self?.observeEventKitChanges() }
        )
      }
    #endif
  }

  /// Hands the reports of passes the engine runs on its own (a push, the
  /// system scheduler, a retry) to ``handleEngineCloudSyncReport(_:)``.
  func connectCloudSyncReports() async {
    await cloudSyncController?.setReportHandler { [weak self] report in
      await self?.handleEngineCloudSyncReport(report)
    }
  }

  /// Listens for `.lorvexCloudKitRemoteChange`, the in-process "sync now"
  /// request (a push that arrived before this store attached, CarPlay
  /// connecting), and refreshes on each one.
  func observeSyncRequests() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexCloudKitRemoteChange)
    for await _ in stream {
      await refresh()
    }
  }

  /// Listens for `CKAccountChanged` (iCloud sign-in/out/switch) and resets the
  /// sync identity on each one.
  func observeCloudKitAccountChanges() async {
    let stream = NotificationCenter.default.notifications(named: .CKAccountChanged)
    for await _ in stream {
      await handleCloudKitAccountChange()
    }
  }

  /// Republishes when the local calendar day rolls over while the app is running.
  /// The widget/complication snapshot bakes day-relative stats (due-today /
  /// overdue / completed-today) at publish time, so without a day-boundary
  /// republish an app foregrounded across midnight would keep serving yesterday's
  /// counts to its glance surfaces. `refresh()` reloads today and republishes the
  /// snapshot (which reloads all widget timelines). Foundation posts
  /// `NSCalendarDayChanged` at midnight and on any shift of the current day (time
  /// zone / clock changes). Mirrors macOS `AppStore.observeCalendarDayChange`.
  func observeCalendarDayChange() async {
    let stream = NotificationCenter.default.notifications(named: .NSCalendarDayChanged)
    for await _ in stream {
      await refresh()
    }
  }

  /// Listens for local database writes outside this store and refreshes the
  /// mobile UI while it is already foregrounded.
  func observeDatabaseChangeSignal() async {
    let stream = NotificationCenter.default.notifications(
      named: DatabaseChangeSignal.didChangeNotification)
    for await notification in stream {
      // A completed CloudKit apply posts an origin-tagged invalidation after it
      // has already reconciled this store. CarPlay and any independent store
      // still need the signal; refreshing the origin again would duplicate the
      // entire fan-out and start another sync cycle.
      if databaseChangeOriginIsSelf(notification) { continue }
      // Await inline so this lifetime observer owns all of its work: cancelling
      // it during teardown cannot leave an untracked refresh task running. Core
      // writes are already burst-coalesced by `DatabaseChangeSignal`, while
      // concurrent lifecycle triggers still converge through `refreshFlight`.
      await refresh()
    }
  }

  func databaseChangeOriginIsSelf(_ notification: Notification) -> Bool {
    guard let origin = notification.object as? MobileStore else { return false }
    return origin === self
  }

  /// Refreshes after a successful in-process notification action (Complete /
  /// Defer / Snooze from the notification's own action buttons), so the app
  /// reflects the mutation and re-plans reminders/badge instead of showing
  /// the task as still open with a stale reminder. Mirrors the macOS
  /// `AppStore.observeBackgroundMutationsApplied` — both post/observe the
  /// same shared `.lorvexBackgroundMutationApplied` name (declared in
  /// `LorvexCloudSync`), posted by ``LorvexMobileAppDelegate``'s
  /// notification-action handlers.
  func observeBackgroundMutationsApplied() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexBackgroundMutationApplied)
    for await _ in stream {
      await refresh()
    }
  }

  /// Surfaces a failed notification action (Complete / Defer / Snooze from a
  /// reminder's own buttons) as a user-visible `errorMessage`, mirroring macOS
  /// `AppStore.observeNotificationActionErrors`. The app delegate posts
  /// `.lorvexNotificationActionError` with the failure's classification
  /// (``LorvexNotificationActionFailure``); without this the write failed, the
  /// notification was consumed, and the task silently stayed open with nothing
  /// shown. A post without a classification (e.g. a snooze failure whose system
  /// error carried no message) falls back to a localized generic string.
  func observeNotificationActionErrors() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexNotificationActionError)
    for await note in stream {
      await surfaceNotificationActionFailure(
        note.userInfo?[LorvexNotificationActionFailure.classificationKey]
          as? UserFacingError.Classification)
      // The delegate also recorded a durable breadcrumb (for the cold-launch
      // case with no live observer); we've surfaced this warm failure, so clear
      // it and don't re-show it on the next foreground.
      MobileNotificationActionErrorHandoff(defaults: defaults).clear()
    }
  }

  /// Drain a notification-action failure recorded while no observer was live
  /// (a cold background launch ran the action, then the process exited before the
  /// UI attached). Called on the next foreground; a failure without a
  /// classification uses the localized fallback. Public: invoked from the
  /// `LorvexMobileApp` @main module.
  public func consumePendingNotificationActionError() async {
    let handoff = MobileNotificationActionErrorHandoff(defaults: defaults)
    guard handoff.hasPendingError else { return }
    let classification = handoff.pendingClassification
    handoff.clear()
    await surfaceNotificationActionFailure(classification)
  }

  private func surfaceNotificationActionFailure(
    _ classification: UserFacingError.Classification?
  ) async {
    if let classification {
      errorMessage = await userFacingBannerMessage(
        for: classification, source: "ios.notification.action_failed")
    } else {
      errorMessage = String(
        localized: "notification.action.failed", defaultValue: "Couldn’t perform that action.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  #if canImport(EventKit)
    func observeEventKitChanges() async {
      let observer = MobileEventKitChangeObserver { [weak self] in
        guard let self else { return }
        await self.refreshLoadedCalendarWindow(fallbackAnchor: self.now())
      }
      await observer.observe()
    }
  #endif

  /// Route a Lorvex CloudKit push by the app's execution state. The engine
  /// fetches on its own when a push arrives; this keeps the app awake for that
  /// work within the push budget. An active app runs the full refresh so the
  /// visible surfaces, widgets, reminders, and badge adopt what arrived; a
  /// background wake runs only the sync pass. Either returns by `deadline`;
  /// the work continues best-effort past it.
  @discardableResult
  public func handleCloudKitPush(
    applicationIsActive: Bool,
    backgroundDeadline: TimeInterval = MobileStore.backgroundPushDrainDeadline
  ) async -> MobileCloudSyncLifecycleResult {
    let race = CloudSyncLifecycleRace()
    let work = Task { @MainActor [weak self] in
      guard let self else { return race.finish(.noData) }
      race.finish(applicationIsActive ? await self.refresh() : await self.runCloudSyncCycle())
    }
    let deadlineTask = Task.detached {
      try? await Task.sleep(nanoseconds: UInt64(max(0, backgroundDeadline) * 1_000_000_000))
      race.finish(.noData)
    }
    let result = await race.value()
    deadlineTask.cancel()
    // Unstructured tasks run to completion after their handle leaves scope;
    // the work is deliberately not cancelled when the deadline wins.
    withExtendedLifetime(work) {}
    return result
  }

  /// Safety deadline for a silent-push wake, comfortably inside Apple's ~30s
  /// content-available budget.
  public static let backgroundPushDrainDeadline: TimeInterval = 22

  /// Runs one sync pass as the app leaves the foreground, so an edit made just
  /// before leaving reaches other devices now rather than at the next launch.
  /// A no-op while sync is off.
  public func flushCloudSyncBeforeSuspension() async {
    guard cloudSyncMode == .live, cloudSyncController != nil else { return }
    await runCloudSyncCycle()
  }

  /// Re-evaluates the sync identity after `CKAccountChanged`. A switch to a
  /// different Apple ID pauses sync until the user adopts the new account; the
  /// same or a first account resumes with a refresh. Best-effort — failures
  /// are recorded, never thrown.
  public func handleCloudKitAccountChange() async {
    guard cloudSyncMode == .live, let cloudSyncController else { return }
    let state = await cloudSyncController.handleAccountChange()
    await applyCloudSyncControllerState(state)
    if state == .running {
      lastCloudSyncRemoteChangeErrorMessage = nil
      await refresh()
    }
  }

  /// Best-effort post-write surfaces: republish the widget snapshot, then
  /// start one sync pass that adopts any peer rows it commits into the primary
  /// UI. The local work is awaited and the pass is not: a pass lasts a CloudKit
  /// round trip with no deadline, and a caller holding a busy flag, an open
  /// sheet, or a task's mutation guard would otherwise hold it that long.
  /// Passes started while one runs coalesce into one trailing pass. A widget
  /// publish failure is swallowed and the pass records its own status fields,
  /// so neither can fail the surrounding mutation.
  func publishMobileSyncSurfaces() async {
    await runLocalRetentionMaintenance()
    _ = try? await publishWidgetSnapshot()
    Task { await self.syncAfterLocalWrite() }
  }

  /// One sync pass after a local write, then adoption of what it committed.
  private func syncAfterLocalWrite() async {
    let syncResult = await runCloudSyncCycle()
    await reloadInboundSurfacesIfNeeded(after: syncResult)
  }

  /// Run local retention off the main actor, best-effort. A no-op for a
  /// non-envelope backend and swallowed on failure — retention GC must never
  /// surface an error or block the refresh. Retention commits in its own
  /// transactions, which SQLite serializes with sync applies. Only a non-live
  /// mode may shed an oversized active outbox backlog.
  func runLocalRetentionMaintenance() async {
    guard let sync = core as? any EnvelopeSyncServicing else { return }
    let includeActiveOutboxCap = cloudSyncMode != .live
    try? await Task.detached(priority: .utility) {
      try sync.runLocalRetentionMaintenance(
        includeActiveOutboxCap: includeActiveOutboxCap)
    }.value
  }
}
