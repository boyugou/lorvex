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

  func setCloudSyncModeFromSettings(_ request: MobileCloudSyncModeRequest) async {
    // A successful deletion supersedes mode intents captured before it. The UI
    // creates this token synchronously in the Binding setter, before spawning
    // its Task, so delayed task scheduling cannot resurrect deleted cloud data.
    guard request.deletionEpoch == cloudDataDeletionEpoch else { return }
    let mode = request.mode
    // A mode switch never interrupts an active cycle, transition, or deletion
    // cleanup. Although the coordinator actor graph is retained, changing the
    // effective mode mid-operation would still reorder consent and runtime
    // state around that operation. Queue the request (latest wins) and apply it
    // atomically at completion; the Settings picker binds to
    // `cloudSyncModeTarget` so it shows the queued target instead of snapping
    // back.
    if isSettingCloudSyncMode || isDataImportRunning || isCloudSyncCycleRunning
      || isCloudDeletionMaintenanceRunning
    {
      pendingCloudSyncMode = mode
      return
    }
    // A direct call supersedes any stale queued request.
    pendingCloudSyncMode = nil
    await applyCloudSyncModeChange(mode)
    await applyPendingCloudSyncModeIfNeeded()
  }

  /// Applies the queued sync-mode request once no transition, cycle, or
  /// refresh is active; a no-op otherwise (the still-active work will call
  /// this again on completion). Loops because a new request can be queued
  /// while an apply's own awaits are in flight.
  func applyPendingCloudSyncModeIfNeeded(
    allowDuringDataImport: Bool = false
  ) async {
    while let pending = pendingCloudSyncMode {
      guard !isSettingCloudSyncMode, !isCloudSyncCycleRunning,
        !isCloudDeletionMaintenanceRunning, !isRefreshing,
        allowDuringDataImport || !isDataImportRunning
      else { return }
      pendingCloudSyncMode = nil
      await applyCloudSyncModeChange(pending)
    }
  }

  /// The actual mode transition: persists the mode, swaps the CloudSync
  /// services, and (for `.live`) lifts a standing deletion pause, registers
  /// the push subscription, and runs a first full refresh. Callers must
  /// ensure no other transition or cycle is active (see
  /// `setCloudSyncModeFromSettings`).
  private func applyCloudSyncModeChange(_ mode: CloudSyncMode) async {
    guard cloudSyncMode != mode else { return }
    isSettingCloudSyncMode = true
    defer { isSettingCloudSyncMode = false }
    MobileSetupPreferences(defaults: defaults).setCloudSyncMode(mode)
    let services = cloudSyncServiceFactory(mode)
    cloudSyncMode = mode
    cloudSyncSubscriber = services.subscriber
    if mode == .live {
      if cloudDataMaintenanceCoordinator == nil {
        cloudDataMaintenanceCoordinator = services.coordinator
      }
      cloudSyncCoordinator = cloudDataMaintenanceCoordinator
    } else {
      cloudSyncCoordinator = nil
    }
    hasRegisteredSubscription = false
    cloudSyncPacing.reset()
    if mode == .live {
      // Turning sync back on is the explicit re-opt-in after a Lorvex
      // iCloud-data deletion: lift the durable pause and enqueue the re-upload
      // BEFORE the first cycle below, so it resumes instead of wedging at the
      // consent gate. A no-op unless a deletion pause is standing.
      await liftCloudDeletionPauseForExplicitReenable()
      await refreshCloudKitAccountAvailability()
      await registerCloudSyncSubscriptionIfNeeded()
      await refreshResettingCloudSyncPacing()
    } else {
      cloudKitAccountAvailability = .available
    }
    await loadRuntimeDiagnostics()
  }

  /// Starts the app-lifetime CloudKit observers once and retains them on the
  /// store. Mirrors the macOS `startLifetimeObserversIfNeeded`: a silent push
  /// triggers a refresh (which drains the outbox and pulls), and an iCloud
  /// account switch resets the sync identity. The store outlives every view, so
  /// these keep running across navigation instead of being cancelled with a
  /// per-view `.task`.
  public func startLifetimeObserversIfNeeded() {
    guard lifetimeObserverTasks.isEmpty else { return }
    DatabaseChangeSignal.startObserving()
    lifetimeObserverTasks = [
      Task { [weak self] in await self?.observeCloudKitRemoteChanges() },
      Task { [weak self] in await self?.observeCloudKitAccountChanges() },
      Task { [weak self] in await self?.observeDatabaseChangeSignal() },
      Task { [weak self] in await self?.observeBackgroundMutationsApplied() },
      Task { [weak self] in await self?.observeNotificationActionErrors() },
      Task { [weak self] in await self?.observeCalendarDayChange() },
      // A one-shot launch attempt resumes namespace deletion even while the
      // user's ordinary Cloud Sync mode remains off.
      Task { [weak self] in await self?.retryPendingCloudDataDeletionCleanup() },
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

  /// Listens for `.lorvexCloudKitRemoteChange` (posted by the app delegate when a
  /// CloudKit silent push arrives) and drains/pulls on each one.
  func observeCloudKitRemoteChanges() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexCloudKitRemoteChange)
    for await _ in stream {
      await handleCloudKitRemoteChange()
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
  /// `.lorvexNotificationActionError` on failure; without this the write failed,
  /// the notification was consumed, and the task silently stayed open with
  /// nothing shown. A post without a message (e.g. a snooze failure whose system
  /// error carried none) falls back to a localized generic string.
  func observeNotificationActionErrors() async {
    let stream = NotificationCenter.default.notifications(named: .lorvexNotificationActionError)
    for await note in stream {
      if let raw = note.userInfo?["errorMessage"] as? String {
        errorMessage = await userFacingBannerMessage(
          forMessage: raw, source: "ios.notification.action_failed")
      } else {
        errorMessage = String(
          localized: "notification.action.failed", defaultValue: "Couldn't perform that action.",
          table: "Localizable", bundle: MobileL10n.bundle)
      }
    }
  }

  #if canImport(EventKit)
    func observeEventKitChanges() async {
      let observer = MobileEventKitChangeObserver { [weak self] in
        guard let self else { return }
        await self.refreshCalendarTimeline(around: self.now())
      }
      await observer.observe()
    }
  #endif

  /// A CloudKit silent push arrived: refresh so the inbound backlog drains and
  /// the UI reflects remote changes. `refresh()` publishes the local snapshot,
  /// runs the sync cycle, then selectively adopts any canonical inbound changes.
  /// A push is a fresh, server-confirmed "remote data changed" signal — the
  /// strongest reason to attempt a pull now — so the breaker/backoff is reset
  /// first, guaranteeing the cycle attempts immediately rather than staying
  /// wedged behind a stale offline-failure window.
  @discardableResult
  public func handleCloudKitRemoteChange() async -> MobileCloudSyncLifecycleResult {
    // Keep the push debt durable until the complete foreground fan-out returns.
    // If the OS completion deadline wins, this refresh continues best-effort;
    // a process termination before it finishes still leaves the handoff for the
    // next activation instead of silently consuming the push up front.
    let handoff = MobileCloudSyncPushHandoff(defaults: defaults)
    let token = handoff.recordPendingPush()
    let startingSuccessfulGeneration = cloudSyncSuccessfulCycleGeneration
    cloudSyncPacing.reset()
    let result = await refresh()
    acknowledgePendingCloudSyncPush(
      token: token, startingSuccessfulGeneration: startingSuccessfulGeneration, result: result)
    return result
  }

  func acknowledgePendingCloudSyncPush(
    token: String?,
    startingSuccessfulGeneration: UInt64,
    result: MobileCloudSyncLifecycleResult
  ) {
    guard let token,
      result != .failed,
      cloudSyncSuccessfulCycleGeneration != startingSuccessfulGeneration,
      lastCloudSyncRemoteChangeErrorMessage == nil
    else { return }
    MobileCloudSyncPushHandoff(defaults: defaults).acknowledgePendingPush(token: token)
  }

  /// Route a silent CloudKit push according to the app's current execution
  /// state. UIKit delivers the same delegate callback while foregrounded and in
  /// the background: an active app must run the full refresh/fan-out, while a
  /// background wake must stay inside the bounded sync-only budget.
  @discardableResult
  public func handleCloudKitPush(
    applicationIsActive: Bool,
    backgroundDeadline: TimeInterval = MobileStore.backgroundPushDrainDeadline
  ) async -> MobileCloudSyncLifecycleResult {
    if applicationIsActive {
      return await refreshForActivePushWithinDeadline(backgroundDeadline)
    }
    return await drainCloudSyncForBackgroundPush(deadline: backgroundDeadline)
  }

  /// Default safety deadline for the background silent-push drain, comfortably
  /// inside Apple's ~30s content-available push budget.
  public static let backgroundPushDrainDeadline: TimeInterval = 22

  /// Bounded inbound drain for a CloudKit silent BACKGROUND push, safe to await
  /// from the app delegate's `didReceiveRemoteNotification` handler.
  ///
  /// A silent push must return within Apple's ~30s budget or the app's background
  /// wakes get throttled. ``handleCloudKitRemoteChange()`` runs the full
  /// foreground fan-out (snapshot, widget, reminders, badge) and up to 64 inbound
  /// pages with NO deadline, so it is unsafe here. This entry instead:
  ///
  /// 1. Durably records the pending push FIRST (``MobileCloudSyncPushHandoff``),
  ///    so however far the bounded drain gets — even nothing — the debt is paid by
  ///    the next foreground/background opportunity, which runs the full refresh
  ///    fan-out this entry deliberately SKIPS and resumes any inbound pages the
  ///    deadline cut short.
  /// 2. Drains the inbound backlog (the sync cycle only — no fan-out) inside a
  ///    task the `deadline` bounds, returning promptly even when a large backlog
  ///    or an in-flight cycle would otherwise overrun the budget. The drain keeps
  ///    running best-effort past a cutoff; its late result is dropped.
  ///
  /// The LOCAL pacing backoff is reset first (a push is a strong "remote changed"
  /// signal), but a server-mandated throttle is preserved (see
  /// ``CloudSyncPacing/reset()``), so the drain still honors an active rate limit.
  ///
  /// Returns the background-fetch result: `.newData` when the bounded drain
  /// applied or fetched anything, `.failed` on a cycle failure, `.noData`
  /// otherwise — including a deadline cutoff, which reports no confirmed data
  /// within budget rather than blocking.
  @discardableResult
  public func drainCloudSyncForBackgroundPush(
    deadline: TimeInterval = MobileStore.backgroundPushDrainDeadline
  ) async -> MobileCloudSyncLifecycleResult {
    MobileCloudSyncPushHandoff(defaults: defaults).recordPendingPush()
    cloudSyncPacing.reset()
    return await drainCloudSyncWithinDeadline(deadline)
  }

  /// Start the complete foreground refresh/fan-out while bounding the app
  /// delegate's fetch-completion contract. The refresh task is intentionally not
  /// cancelled when the deadline wins: an active app should still adopt the
  /// remote rows into its visible UI, widgets, reminders, and badge. The durable
  /// handoff remains set until that task actually finishes.
  private func refreshForActivePushWithinDeadline(
    _ deadline: TimeInterval
  ) async -> MobileCloudSyncLifecycleResult {
    let race = CloudSyncLifecycleRace()
    let refreshTask = Task { @MainActor [weak self] in
      race.finish(await self?.handleCloudKitRemoteChange() ?? .noData)
    }
    let deadlineTask = Task.detached {
      try? await Task.sleep(nanoseconds: UInt64(max(0, deadline) * 1_000_000_000))
      race.finish(.noData)
    }
    let result = await race.value()
    deadlineTask.cancel()
    // Keep an explicit handle alive through the race. Unstructured tasks run to
    // completion even after the handle leaves scope; do not cancel this one on a
    // deadline because it owns the promised foreground fan-out.
    withExtendedLifetime(refreshTask) {}
    return result
  }

  /// Run the drain (``runCloudSyncCycle()``) but return after at most `deadline`
  /// seconds, whichever comes first. The drain runs in an unstructured task so a
  /// deadline cutoff returns immediately without awaiting the still-running
  /// (possibly CloudKit-blocked) cycle; the loser of the race is cancelled
  /// best-effort.
  ///
  /// The deadline timer runs OFF the main actor so it fires on its own schedule
  /// even while the main actor is busy — a safety deadline that could be starved
  /// by main-actor load would not be a bound at all.
  private func drainCloudSyncWithinDeadline(
    _ deadline: TimeInterval
  ) async -> MobileCloudSyncLifecycleResult {
    let race = CloudSyncLifecycleRace()
    let drainTask = Task { @MainActor [weak self] in
      race.finish(await self?.runCloudSyncCycle() ?? .noData)
    }
    let deadlineTask = Task.detached {
      try? await Task.sleep(nanoseconds: UInt64(max(0, deadline) * 1_000_000_000))
      race.finish(.noData)
    }
    let result = await race.value()
    // The loser is now moot: cancel the pending sleep and signal the drain. Its
    // detached CloudKit work does not observe cancellation, but the recorded
    // handoff guarantees a later foreground refresh finishes it and fans out.
    deadlineTask.cancel()
    drainTask.cancel()
    return result
  }

  /// Consumes a push handoff the app delegate persisted because the CloudKit
  /// silent push arrived before this store was attached (see
  /// ``MobileCloudSyncPushHandoff``), running the drain the push asked for.
  /// Called once on store attachment; returns `nil` when no handoff was
  /// pending (no drain owed), otherwise the drain's lifecycle result.
  @discardableResult
  public func consumePendingCloudSyncPushHandoffIfNeeded() async
    -> MobileCloudSyncLifecycleResult?
  {
    guard MobileCloudSyncPushHandoff(defaults: defaults).hasPendingPush else { return nil }
    return await handleCloudKitRemoteChange()
  }

  /// Re-evaluates sync identity after a CKAccountChanged notification. The
  /// process-local subscription flag and breaker reset immediately. Checkpoints
  /// remain account+generation qualified: a real switch pauses, while an
  /// unchanged/first account immediately re-enters the ordinary refresh path to
  /// re-register and drain with its valid cursor. Best-effort — gate-state
  /// failures are recorded, never thrown.
  public func handleCloudKitAccountChange() async {
    hasRegisteredSubscription = false
    cloudSyncPacing.reset()
    guard cloudSyncMode == .live else { return }
    guard let cloudSyncCoordinator else { return }
    var shouldResumeSameAccountSync = false
    do {
      // A switch to a different Apple ID suppresses the backfill (see the returned
      // AccountChangeBackfillDecision) so this device's data is not commingled
      // into the new account's zone; an explicit opt-in via
      // confirmBackfillIntoCurrentAccount(sync:expectedPauseReason:) is then required.
      let decision = try await cloudSyncCoordinator.handleAccountChange()
      shouldResumeSameAccountSync = decision == .backfilled
      if decision == .backfillFailed {
        lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
          forMessage: "CloudKit full-resync backfill failed; sync is paused until retry.",
          source: "ios.cloud_sync.account_change")
      } else {
        lastCloudSyncRemoteChangeErrorMessage = nil
      }
    } catch {
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "ios.cloud_sync.account_change")
    }
    // Surface a durable pause the account change may have set (a switch to a
    // different Apple ID) so the UI can offer the adopt action.
    await refreshCloudSyncPauseReason()
    // An unavailable-account cycle cancels its retry wake because no durable
    // deadline can predict when iCloud will return. CKAccountChanged is the
    // recovery edge: for the unchanged/first account, immediately re-enter the
    // normal refresh flight so subscription registration and one serialized
    // sync drain resume without waiting for an unrelated scene activation.
    if shouldResumeSameAccountSync {
      // The coordinator call may have queued behind a cycle that failed after
      // the notification's eager reset. Reset at the recovery edge too so the
      // refresh itself is never rejected by stale pacing state.
      cloudSyncPacing.reset()
      _ = await refresh()
    }
  }

  /// Registers the private-database push subscription the first time only.
  /// Registration is an idempotent CloudKit upsert; the flag avoids re-issuing it
  /// on every refresh. A failure is recorded and the flag stays false so the next
  /// refresh retries. No-op (succeeds silently) when sync is off.
  func registerCloudSyncSubscriptionIfNeeded() async {
    #if os(visionOS)
      // visionOS converges through foreground/scene-active refresh. It has no
      // remote-notification delegate, so registering a silent-push
      // subscription would create server work with no delivery path.
      return
    #else
      guard !hasRegisteredSubscription else { return }
      do {
        try await cloudSyncSubscriber.registerSubscription()
        hasRegisteredSubscription = true
        lastCloudSyncSubscriptionErrorMessage = nil
      } catch {
        lastCloudSyncSubscriptionErrorMessage = await cloudSyncUserFacingErrorMessage(
          for: error, source: "ios.cloud_sync.subscription")
      }
    #endif
  }

  /// Best-effort post-write surfaces: republish the widget snapshot, run one
  /// CloudSync cycle (drain outbox + pull), then adopt any peer rows that cycle
  /// committed into the primary UI. Mirrors the macOS
  /// `publishAppleSyncSurfaces`. Both are invisible and best-effort: a widget
  /// publish failure is swallowed and the cycle records its own status fields, so
  /// neither can fail the surrounding refresh/mutation.
  func publishMobileSyncSurfaces() async {
    // Always-safe policy/age retention cannot rely on a live apply: account
    // gates, pauses, pacing, and transport failures can suppress the cycle for
    // an arbitrary period. Preserve every active outbox row in live mode, where
    // a paused full-resync backlog may legitimately exceed the sync-off cap.
    await runLocalRetentionMaintenance()
    _ = try? await publishWidgetSnapshot()
    let syncResult = await runCloudSyncCycle()
    await reloadInboundSurfacesIfNeeded(after: syncResult)
  }

  /// Run local retention under the App's retained CloudSync operation gate,
  /// best-effort. A no-op for a non-envelope backend and swallowed on failure —
  /// retention GC must never surface an error or block the refresh. A
  /// coordinator-less test/preview shell keeps the direct off-actor fallback.
  /// Mirrors the macOS `AppStore.runLocalRetentionMaintenance`.
  func runLocalRetentionMaintenance() async {
    guard let sync = core as? any EnvelopeSyncServicing else { return }
    if let coordinator = cloudDataMaintenanceCoordinator ?? cloudSyncCoordinator {
      try? await coordinator.runLocalRetentionMaintenance(
        sync: sync,
        activeOutboxCapPolicy: { @MainActor [weak self] in
          guard let self else { return false }
          return self.cloudSyncMode != .live
        })
      return
    }
    let includeActiveOutboxCap = cloudSyncMode != .live
    try? await Task.detached(priority: .utility) {
      try sync.runLocalRetentionMaintenance(
        includeActiveOutboxCap: includeActiveOutboxCap)
    }.value
  }

  /// Run one invisible sync cycle off the main actor, draining the inbound
  /// backlog and pacing failures. Best-effort: account-gating and errors are
  /// recorded in the status fields and never thrown. No-ops when sync is not
  /// `.live` / iCloud is unavailable.
  ///
  /// Pacing gates *when* a cycle runs: `shouldRun` skips while a prior attempt is
  /// inside its backoff window or the breaker is open. A nil report (account
  /// unavailable / non-envelope backend) is neither success nor failure. A cycle
  /// "made no progress" — a push failed while nothing pushed or fetched — counts
  /// as a failure that advances the backoff; any progress resets it.
  ///
  /// A sync-mode change requested mid-cycle was queued rather than applied
  /// (rebuilding the coordinator would race two store actor sets over one
  /// sync-state directory); the cycle's completion applies it here.
  @discardableResult
  func runCloudSyncCycle() async -> MobileCloudSyncLifecycleResult {
    let outcome = await cloudSyncCycleFlight.run(
      body: { await runCloudSyncCycleBody() },
      afterDrain: { await applyPendingCloudSyncModeIfNeeded() })
    // Preserve the previous successful report when this trigger could not run
    // (sync off, account unavailable, pacing, or a thrown transport error),
    // matching the pre-single-flight status semantics. A real report replaces
    // it with the aggregate of every coalesced pass.
    if let report = outcome.report {
      lastCloudSyncCycleReport = report
    }
    return outcome.lifecycle
  }

  private func runCloudSyncCycleBody() async -> MobileCloudSyncCycleOutcome {
    guard !isDataImportRunning, cloudSyncMode == .live else {
      cancelCloudSyncRetryWake()
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }
    guard let cloudSyncCoordinator else {
      cancelCloudSyncRetryWake()
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }
    let snapshotCore = core
    guard snapshotCore is any EnvelopeSyncServicing else {
      cancelCloudSyncRetryWake()
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }
    let now = self.now()
    // ±10% jitter to desynchronize backoff across devices.
    guard cloudSyncPacing.shouldRun(now: now, jitterFraction: Double.random(in: -1...1)) else {
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }
    cloudSyncPacing.recordAttempt(now: now)

    let accountAvailability =
      (try? await cloudSyncCoordinator.accountChecker.checkAccountStatus()) ?? .couldNotDetermine
    cloudKitAccountAvailability = accountAvailability
    guard accountAvailability == .available else {
      if accountAvailability == .couldNotDetermine
        || accountAvailability == .temporarilyUnavailable
      {
        cloudSyncPacing.recordFailure()
        updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
      } else {
        cancelCloudSyncRetryWake()
      }
      return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
    }

    do {
      // CloudKit I/O + apply transactions run off @MainActor in a detached task.
      let report = try await Task.detached(priority: .utility) {
        let signpost = LorvexSignpost.begin(.cloudSync)
        defer { LorvexSignpost.end(signpost) }
        return try await cloudSyncCoordinator.runDrainingCycle(core: snapshotCore)
      }.value
      // Surface any durable pause the cycle just set (a closed-app account switch
      // is detected inside the cycle, not via CKAccountChanged) or cleared.
      await refreshCloudSyncPauseReason()
      guard let report else {
        await reconcileCloudSyncRetryWakeAfterNilReport(using: cloudSyncCoordinator)
        return MobileCloudSyncCycleOutcome(lifecycle: .noData, report: nil)
      }
      if Self.cloudSyncCycleMadeNoProgress(report) {
        cloudSyncPacing.recordFailure()
        lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
          forMessage: "CloudKit push failed without making progress",
          source: "ios.cloud_sync.cycle")
        updateCloudSyncRetryWake(after: report, retryCurrentWork: true)
        return MobileCloudSyncCycleOutcome(lifecycle: .failed, report: report)
      } else {
        cloudSyncPacing.recordSuccess()
        cloudSyncSuccessfulCycleGeneration &+= 1
        lastCloudSyncRemoteChangeSucceededAt = now
        lastCloudSyncRemoteChangeErrorMessage = nil
        updateCloudSyncRetryWake(after: report, retryCurrentWork: false)
        return MobileCloudSyncCycleOutcome(
          lifecycle: Self.cloudSyncCycleMadeDataAvailable(report) ? .newData : .noData,
          report: report)
      }
    } catch {
      let partialReport = (error as? CloudSyncPartialCycleFailure)?.partialReport
      await refreshCloudSyncPauseReason()
      // A CloudKit `.requestRateLimited` / `.serviceUnavailable` names the
      // earliest instant the server will accept a retry; honor it as a throttle
      // that survives the next push/activation reset, so a user trigger cannot
      // stampede past an active server rate limit.
      if let retryAfter = CloudSyncTransientClassifier.serverRetryAfter(error) {
        cloudSyncPacing.recordServerThrottle(retryAfter: retryAfter, now: now)
      }
      cloudSyncPacing.recordFailure()
      lastCloudSyncRemoteChangeErrorMessage = await cloudSyncUserFacingErrorMessage(
        for: error, source: "ios.cloud_sync.cycle")
      updateCloudSyncRetryWake(after: partialReport, retryCurrentWork: true)
      return MobileCloudSyncCycleOutcome(
        lifecycle: partialReport.map(Self.cloudSyncCycleMadeDataAvailable) == true
          ? .newData : .failed,
        report: partialReport)
    }
  }

  private func reconcileCloudSyncRetryWakeAfterNilReport(
    using coordinator: CloudSyncEngineCoordinator
  ) async {
    guard cloudSyncPauseReason == nil else {
      cancelCloudSyncRetryWake()
      return
    }
    let availability =
      (try? await coordinator.accountChecker.checkAccountStatus()) ?? .couldNotDetermine
    cloudKitAccountAvailability = availability
    switch availability {
    case .available:
      // No result was consumed across the account/generation boundary, so the
      // local outbox is still authoritative pending work. Back off, then retry
      // through the ordinary path even if the generation-change push is lost.
      cloudSyncPacing.recordFailure()
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
    case .couldNotDetermine, .temporarilyUnavailable:
      cloudSyncPacing.recordFailure()
      updateCloudSyncRetryWake(after: nil, retryCurrentWork: true)
    case .noAccount, .restricted:
      cancelCloudSyncRetryWake()
    }
  }

  /// A non-nil report "made no progress" when a push failed and neither
  /// direction advanced: nothing pushed and nothing fetched. The coordinator
  /// folds a push throw into `failedPushCount` rather than re-throwing, so this
  /// is the report-shaped half of the failure predicate; the thrown-error half
  /// is handled in `runCloudSyncCycle`'s `catch`.
  static func cloudSyncCycleMadeNoProgress(_ report: CloudSyncCycleReport) -> Bool {
    report.failedPushCount > 0 && report.pushedRecordCount == 0 && report.fetchedRecordCount == 0
  }

  static func cloudSyncCycleMadeDataAvailable(_ report: CloudSyncCycleReport) -> Bool {
    report.pushedRecordCount > 0
      || report.fetchedRecordCount > 0
      || report.inbound.applied > 0
      || report.inbound.deferred > 0
      || report.inbound.remapped > 0
      || report.inbound.drainReplayed > 0
  }
}

/// One-shot bridge that resolves its awaiter with whichever of the bounded
/// background-push drain or its deadline finishes first (see
/// ``MobileStore/drainCloudSyncForBackgroundPush(deadline:)``).
///
/// Lock-guarded so the two racing tasks — the main-actor drain and the
/// off-main deadline timer — can call ``finish(_:)`` from different executors
/// without a data race; only the first takes effect and resumes the awaiter
/// exactly once. A result delivered before the awaiter suspends is stashed and
/// returned immediately, so the race is correct regardless of task-scheduling
/// order.
private final class CloudSyncLifecycleRace: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<MobileCloudSyncLifecycleResult, Never>?
  private var pending: MobileCloudSyncLifecycleResult?
  private var finished = false

  func value() async -> MobileCloudSyncLifecycleResult {
    await withCheckedContinuation { continuation in
      lock.lock()
      if let pending {
        lock.unlock()
        continuation.resume(returning: pending)
      } else {
        self.continuation = continuation
        lock.unlock()
      }
    }
  }

  func finish(_ result: MobileCloudSyncLifecycleResult) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let awaiting = continuation
    continuation = nil
    if awaiting == nil { pending = result }
    lock.unlock()
    awaiting?.resume(returning: result)
  }
}
