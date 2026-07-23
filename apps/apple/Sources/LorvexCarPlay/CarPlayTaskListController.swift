// CarPlayTaskListController.swift
// LorvexCarPlay
//
// PROVISIONING NOTE: Activating the CarPlay scene on a real device requires
// the Apple-approved com.apple.developer.carplay-communication entitlement.
// This controller and the scene delegate compile without that entitlement; the
// runtime scene is only reachable after provisioning is approved and the
// template entitlement is merged into the signed iOS app target.
//
// See docs/SURFACE_DESIGN.md §CarPlay for the full provisioning checklist.

import Foundation
import LorvexCore

/// Platform-independent controller that loads active tasks + Focus tasks from
/// LorvexCoreServicing and exposes them as lists of rows suitable for
/// presentation in any thin UI layer (CarPlay, widget previews, tests).
///
/// `refresh()` fetches tasks and Focus state in one async pass.
/// `complete(id:)` calls `completeTask` and re-fetches automatically.
///
/// This type contains NO CarPlay imports and is fully testable on any platform.
@MainActor
public final class CarPlayTaskListController {

  // MARK: - State

  /// Open tasks from the uncapped Today-pool query path (excludes tasks also in
  /// the Focus plan to prevent double-counting; Focus takes priority). This
  /// intentionally does not use `loadToday()`, whose snapshot is priority-capped
  /// for dashboard use, and does not use the broad open-task corpus.
  public private(set) var todayRows: [Row] = []

  /// Tasks in the current Focus plan that are still actionable (open or started).
  public private(set) var focusRows: [Row] = []

  /// Set when `refresh()` fails. The CarPlay scene renders a Retry row when
  /// this is non-nil. Callers should set it to a driver-safe message — use
  /// `driverSafeErrorMessage(for:)` to map a raw error rather than exposing
  /// `error.localizedDescription` (a low-level Swift string) on the car screen.
  public var errorMessage: String?

  /// Maps any load error to a short, glanceable, driver-appropriate string.
  /// Deliberately does not surface the underlying error text — a CarPlay
  /// surface should read at a glance, not show a stack-trace-flavored message.
  public static func driverSafeErrorMessage(for error: any Error) -> String {
    String(
      localized: "carplay.error.load_tasks",
      defaultValue: "Couldn't load tasks — tap to retry.",
      table: "Localizable",
      bundle: CarPlayL10n.bundle)
  }

  // MARK: - Private

  private let core: any LorvexCoreServicing

  /// The storage-frame instant for the day after the core's configured logical
  /// day. Product timezone owns "tomorrow"; the CarPlay process's timezone does
  /// not get to fork a synced planned-date identity.
  private static func tomorrowDate(after logicalDay: String) throws -> Date {
    guard
      let tomorrow = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: 1),
      let date = LorvexDateFormatters.ymdUTC.date(from: tomorrow)
    else {
      throw LorvexCoreError.validation(
        field: "date", message: "The configured logical day is invalid.")
    }
    return date
  }

  // MARK: - Init

  /// - Parameter core: The service to load tasks from. Defaults to the mobile
  ///   HLC surface when nil.
  public init(core: (any LorvexCoreServicing)? = nil) {
    self.core = core ?? LorvexCoreRuntimeFactory.makeForMobile()
  }

  // MARK: - Public API

  /// Loads open tasks and the current focus plan, then updates `todayRows`
  /// and `focusRows`.
  ///
  /// Throws if either read fails. The two core reads run concurrently via
  /// `async let` since they are independent.
  public func refresh() async throws {
    let dateString = try await core.getSessionContext().date

    async let todayTasks = core.getTodayTasks(date: dateString, limit: 100, offset: 0)
    async let focusPlanTask = core.loadCurrentFocus(date: dateString)

    let taskPage = try await todayTasks
    let focusPlan = try await focusPlanTask

    let todayPool = taskPage.tasks
    let focusTasks = try await loadActionableFocusTasks(
      ids: focusPlan?.taskIDs ?? [],
      firstPageTasks: todayPool
    )

    focusRows = focusTasks
      .map { Row(id: $0.id, title: $0.title, isFocus: true) }

    let focusIDSet = Set(focusRows.map(\.id))
    todayRows = todayPool
      .filter { !focusIDSet.contains($0.id) }
      .map { Row(id: $0.id, title: $0.title, isFocus: false) }
  }

  /// Completes the task with the given `id` and refreshes both lists.
  /// Throws if the task is not found or the service call fails.
  public func complete(id: String) async throws {
    _ = try await core.completeTask(id: id)
    try await refresh()
  }

  /// Defers the task with the given `id` to tomorrow in the configured product
  /// timezone, stored at the UTC-anchored planned-day instant, and refreshes both
  /// lists. The task drops out of Today until tomorrow.
  /// Throws if the task is not found or the service call fails.
  public func deferToTomorrow(id: String) async throws {
    let logicalDay = try await core.getSessionContext().date
    _ = try await core.deferTask(id: id, until: Self.tomorrowDate(after: logicalDay))
    try await refresh()
  }

  /// Removes the task with the given `id` from today's Focus plan and refreshes
  /// both lists. The task stays open and reappears under Today if still due, so
  /// this only un-focuses — it never completes or cancels.
  /// Throws if the service call fails.
  public func removeFromFocus(id: String) async throws {
    let logicalDay = try await core.getSessionContext().date
    _ = try await core.removeFromCurrentFocus(date: logicalDay, taskID: id)
    try await refresh()
  }

  // MARK: - Internal

  private func loadActionableFocusTasks(
    ids: [LorvexTask.ID],
    firstPageTasks: [LorvexTask]
  ) async throws -> [LorvexTask] {
    guard !ids.isEmpty else { return [] }
    var tasksByID = Dictionary(uniqueKeysWithValues: firstPageTasks.map { ($0.id, $0) })
    for id in ids where tasksByID[id] == nil {
      let task: LorvexTask
      do {
        task = try await core.loadTask(id: id)
      } catch LorvexCoreError.taskNotFound {
        continue
      }
      // A started (in_progress) focus task is actionable and stays on the car
      // screen; only resolved (completed/cancelled) or parked work is dropped.
      guard task.status.isActionable else {
        continue
      }
      tasksByID[id] = task
    }
    return ids.compactMap { tasksByID[$0] }
  }

}
