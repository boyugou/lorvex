import Foundation
import LorvexCore
import LorvexWidgetKitSupport

/// Provides Today's list and habits for the watch surface.
///
/// Refresh reads Today's list in Today's order (started tasks first, then by
/// priority and due date) with each task's saved time: from the phone's
/// replica on a real watch, or from a writable core in tests. Which task leads
/// depends on the clock (``orderedTasks(at:)``), so views resolve it as they
/// draw. Task actions dispatch through the phone forwarder, or the core in
/// tests.
@MainActor
@Observable
public final class LorvexWatchStore {
  enum Backend {
    case core(any LorvexCoreServicing)
    case snapshot(url: URL)
    case snapshotUnavailable(WidgetSnapshotFallback)
  }

  /// Today's tasks still to do, in Today's order: started tasks first, then by
  /// priority and due date. On the snapshot backend this is the head of the
  /// list the phone sent; ``moreCount`` counts the rest.
  public internal(set) var tasks: [LorvexTask] = []

  /// Tasks on Today beyond ``tasks``: the phone sends the head of a long list
  /// together with the whole list's length.
  public internal(set) var moreCount = 0

  /// Today's habits with completion progress, for wrist check-off.
  public internal(set) var habits: [WidgetSnapshot.HabitSummary] = []

  /// Tasks completed on the logical day.
  public internal(set) var completedTodayCount = 0

  /// Each listed task's saved time today, in minutes since midnight of the
  /// product day (in ``timezone``). A task without a time is absent.
  public internal(set) var savedTimes: [LorvexTask.ID: Range<Int>] = [:]

  /// The listed tasks that wait on an unfinished task, as the phone (or the
  /// core) last reported them: their rows read "Blocked", and Start is not
  /// offered for them, since the phone would refuse it.
  public internal(set) var blockedTaskIDs: Set<LorvexTask.ID> = []

  /// The product day's timezone identifier; nil reads the clock in the
  /// watch's own zone.
  public internal(set) var timezone: String?

  /// Day identity carried by the core session or accepted phone snapshot.
  /// Snapshot-backed mutations reuse this exact value instead of recomputing a
  /// day in the watch process's timezone.
  public internal(set) var logicalDay: String?

  /// Non-nil when an async operation is in flight.
  public internal(set) var isLoading: Bool = false

  /// The last error from a refresh or complete call, if any.
  public internal(set) var error: Error?

  /// Human-readable source status for compact watch surfaces.
  public internal(set) var snapshotStatusText: String = String(
    localized: "watch.status.not_refreshed", defaultValue: "Not refreshed",
    table: "Localizable", bundle: WatchL10n.bundle)

  /// How long ago the phone built the replica on screen ("3h ago"), once it is
  /// old enough that the list may have changed since (the widgets' warning
  /// threshold); nil while it is recent or on the core backend.
  public internal(set) var staleAgeLabel: String?

  /// Short task title entered from the watch quick-capture surface.
  public var captureTitle: String = ""

  /// Durable phone-delivery state reported by the production WatchConnectivity
  /// forwarder. Pending commands have already been persisted locally; rejected
  /// commands remain visible until explicitly dismissed.
  public internal(set) var deliveryStatus: LorvexWatchDeliveryStatus = .empty

  /// True while a `refresh()` fan-out is in flight. A second caller that arrives
  /// mid-refresh does not start a parallel run; it records `refreshPending` so
  /// the in-flight refresh reruns once when it finishes. Serializing the bodies
  /// is what prevents a slow *failing* refresh from wiping the state a faster
  /// refresh that started later already populated (the catch block resets
  /// `tasks` / `habits` to empty).
  @ObservationIgnored private var isRefreshing = false

  /// Set when a refresh is requested while one is already in flight; the
  /// in-flight refresh reruns exactly once after it completes, collapsing any
  /// number of mid-flight triggers into a single rerun.
  @ObservationIgnored private var refreshPending = false

  let backend: Backend
  let logicalDayOverride: String?
  let now: @Sendable () -> Date
  let mutationForwarder: (any LorvexWatchMutationForwarding)?

  /// Builds a store backed by a writable core service — a direct-DB path that
  /// bypasses the watch's read-only-snapshot architecture, so it is `internal`
  /// and intended ONLY for tests (`@testable import LorvexWatch`). Production
  /// always builds a `.snapshot` / `.snapshotUnavailable` backend via
  /// `LorvexWatchStoreFactory`; the watch never writes a DB directly.
  init(
    core: any LorvexCoreServicing,
    logicalDayOverride: String? = nil,
    now: @escaping @Sendable () -> Date = Date.init,
    mutationForwarder: (any LorvexWatchMutationForwarding)? = nil
  ) {
    self.backend = .core(core)
    self.logicalDayOverride = logicalDayOverride
    self.now = now
    self.mutationForwarder = mutationForwarder
  }

  public init(
    snapshotURL: URL,
    now: @escaping @Sendable () -> Date = Date.init,
    mutationForwarder: (any LorvexWatchMutationForwarding)? = nil
  ) {
    self.backend = .snapshot(url: snapshotURL)
    self.logicalDayOverride = nil
    self.now = now
    self.mutationForwarder = mutationForwarder
  }

  public init(
    snapshotUnavailable fallback: WidgetSnapshotFallback,
    now: @escaping @Sendable () -> Date = Date.init,
    mutationForwarder: (any LorvexWatchMutationForwarding)? = nil
  ) {
    self.backend = .snapshotUnavailable(fallback)
    self.logicalDayOverride = nil
    self.now = now
    self.mutationForwarder = mutationForwarder
  }

  /// Loads Today's list, its saved times, and today's habits.
  ///
  /// Coalesces concurrent triggers rather than running overlapping bodies: a
  /// request arriving while a refresh is in flight sets `refreshPending` and
  /// returns, and the in-flight refresh reruns once after completing. This keeps
  /// a slow failing refresh from clobbering the state a later, faster refresh
  /// already populated. Re-entrancy-safe on `@MainActor`: the flags are read and
  /// written without an intervening suspension before the guard.
  public func refresh() async {
    guard !isRefreshing else {
      refreshPending = true
      return
    }
    isRefreshing = true
    isLoading = true
    defer {
      isRefreshing = false
      isLoading = false
    }
    repeat {
      refreshPending = false
      await performRefresh()
    } while refreshPending
  }

  private func performRefresh() async {
    error = nil
    do {
      switch backend {
      case .core(let core):
        let today = try await core.loadToday()
        let dateString: String
        if let logicalDayOverride {
          dateString = logicalDayOverride
        } else if let capturedDay = today.logicalDay {
          dateString = capturedDay
        } else {
          dateString = try await core.getSessionContext().date
        }
        logicalDay = dateString
        timezone = today.timezone
        let listed = today.tasks.filter { $0.status.isActionable }
        savedTimes = listed.times(on: dateString)
        blockedTaskIDs = today.blockedTaskIDs
        tasks = listed
        moreCount = 0
        completedTodayCount = (try? await core.loadWidgetStatsSource().completedTodayTasks.count) ?? 0
        let habitCatalog = try await core.loadHabits(date: dateString)
        habits = habitCatalog.habits
          .filter { !$0.archived }
          .map {
            WidgetSnapshot.HabitSummary(
              id: $0.id, name: $0.name, icon: $0.icon,
              completedToday: $0.completionsToday, target: $0.targetCount, color: $0.color)
          }
        snapshotStatusText = String(
          localized: "watch.status.live", defaultValue: "Live from Lorvex",
          table: "Localizable", bundle: WatchL10n.bundle)
      case .snapshot(let url):
        try refreshFromSnapshot(url: url)
        reapplyPendingTaskCommands()
      case .snapshotUnavailable(let fallback):
        throw LorvexWatchSnapshotError.unavailable(fallback)
      }
    } catch {
      logicalDay = nil
      staleAgeLabel = nil
      tasks = []
      moreCount = 0
      habits = []
      completedTodayCount = 0
      savedTimes = [:]
      blockedTaskIDs = []
      if case LorvexWatchSnapshotError.unavailable(let fallback) = error {
        snapshotStatusText = Self.snapshotUnavailableStatusText(fallback)
      } else {
        snapshotStatusText = String(
          localized: "watch.status.unavailable", defaultValue: "Snapshot unavailable",
          table: "Localizable", bundle: WatchL10n.bundle)
      }
      self.error = error
    }
  }

  /// Receives journal state from the connectivity forwarder. Kept as a small
  /// main-actor seam so the forwarder never mutates observable UI state from a
  /// WCSession delegate callback.
  public func updateDeliveryStatus(_ status: LorvexWatchDeliveryStatus) {
    deliveryStatus = status
  }

  /// The newest durably journaled capture still awaiting a phone application
  /// ACK. This is derived from the journal status rather than callback timing or
  /// title equality, so an immediate ACK cannot leave a stale pending banner.
  public var pendingCaptureTitle: String? {
    deliveryStatus.pendingCommands.reversed().compactMap { command -> String? in
      guard case .captureTask(let title) = command.mutation else { return nil }
      return title
    }.first
  }

  /// Explicitly removes a terminal rejected command from the durable journal.
  /// Pending/retryable commands cannot be dismissed through this surface.
  public func dismissRejectedCommand(id: String) async {
    guard let deliveryManager = mutationForwarder as? any LorvexWatchDeliveryManaging else {
      return
    }
    await deliveryManager.dismissRejectedCommand(id: id)
  }

  /// Asks the paired iPhone for a fresh replica, then reloads Today. The phone
  /// rebuilds it on request even from the background, which is what recovers a
  /// missing replica or one left over from an earlier day.
  public func requestReplicaAndRefresh() async {
    if let deliveryManager = mutationForwarder as? any LorvexWatchDeliveryManaging {
      await deliveryManager.requestReplica()
    }
    await refresh()
  }

  /// True when Today failed to load because the watch holds no current replica
  /// (none yet, or one from an earlier day), which a replica request can fix.
  public var needsReplica: Bool {
    guard case LorvexWatchSnapshotError.unavailable(let fallback)? = error else { return false }
    return fallback.reason == .missingFile || fallback.reason == .expiredDay
  }

  /// Foreground activation nudge for commands retained across a prior process
  /// lifetime or connectivity outage.
  public func drainPendingCommands() async {
    guard let deliveryManager = mutationForwarder as? any LorvexWatchDeliveryManaging else {
      return
    }
    await deliveryManager.drain()
  }
}
