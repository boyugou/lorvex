import Foundation
import LorvexCore
import LorvexWidgetKitSupport

/// Provides the current focus plan and task list for the watch surface.
///
/// Refresh loads the focus plan for today and resolves the first actionable task
/// in the plan as the primary focus item. Task actions dispatch through the
/// writable core service and refresh afterwards.
@MainActor
@Observable
public final class LorvexWatchStore {
  enum Backend {
    case core(any LorvexCoreServicing)
    case snapshot(url: URL)
    case snapshotUnavailable(WidgetSnapshotFallback)
  }

  /// The resolved current focus plan for today, or `nil` when none is set.
  public internal(set) var currentFocus: CurrentFocusPlan?

  /// The first actionable task from `currentFocus.taskIDs`, resolved against today's task list.
  public internal(set) var primaryTask: LorvexTask?

  /// Actionable tasks in the current focus plan, preserving the plan order.
  public internal(set) var focusTasks: [LorvexTask] = []

  /// Today's habits with completion progress, for wrist check-off.
  public internal(set) var habits: [WidgetSnapshot.HabitSummary] = []

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
  /// `currentFocus` / `focusTasks` / `habits` to nil/empty).
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

  /// Loads the current focus plan for today and resolves the primary task.
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
        let focus = try await core.loadCurrentFocus(date: dateString)
        currentFocus = focus
        focusTasks = try await resolvedFocusTasks(
          focus: focus, logicalDay: dateString, core: core)
        primaryTask = focusTasks.first
        let habitCatalog = try await core.loadHabits(date: dateString)
        habits = habitCatalog.habits
          .filter { !$0.archived }
          .map {
            WidgetSnapshot.HabitSummary(
              id: $0.id, name: $0.name, icon: $0.icon,
              completedToday: $0.completionsToday, target: $0.targetCount)
          }
        snapshotStatusText = String(
          localized: "watch.status.live", defaultValue: "Live from Lorvex",
          table: "Localizable", bundle: WatchL10n.bundle)
      case .snapshot(let url):
        try refreshFromSnapshot(url: url)
      case .snapshotUnavailable(let fallback):
        throw LorvexWatchSnapshotError.unavailable(fallback)
      }
    } catch {
      currentFocus = nil
      logicalDay = nil
      primaryTask = nil
      focusTasks = []
      habits = []
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

  /// Foreground activation nudge for commands retained across a prior process
  /// lifetime or connectivity outage.
  public func drainPendingCommands() async {
    guard let deliveryManager = mutationForwarder as? any LorvexWatchDeliveryManaging else {
      return
    }
    await deliveryManager.drain()
  }
}
