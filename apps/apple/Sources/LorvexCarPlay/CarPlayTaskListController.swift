// CarPlayTaskListController.swift
// LorvexCarPlay
//
// PROVISIONING NOTE: Activating the CarPlay scene on a real device requires
// the Apple-approved com.apple.developer.carplay-communication entitlement.
// This controller and the scene delegate compile without that entitlement; the
// runtime scene is only reachable after provisioning is approved and the
// template entitlement is merged into the signed iOS app target. A simulator
// build can be made CarPlay-capable with script/carplay_sim_enable.sh.
//
// See docs/SURFACE_DESIGN.md §CarPlay for the full provisioning checklist.

import Foundation
import LorvexCore

/// Platform-independent controller that reads Today's list and the day's
/// times from `LorvexCoreServicing` and exposes them as the rows a thin UI
/// layer (CarPlay, previews, tests) presents.
///
/// `refresh()` reads everything in one async pass. The mutations (`complete`,
/// `deferToTomorrow`) write through the core and re-read automatically.
///
/// This type contains NO CarPlay imports and is fully testable on any platform.
@MainActor
public final class CarPlayTaskListController {

  // MARK: - State

  /// Today's tasks in Today's order (started tasks first, then by priority and
  /// due date), each with its time when the day's schedule gives it one.
  public private(set) var todayRows: [Row] = []

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
      defaultValue: "Couldn’t load tasks — tap to retry.",
      table: "Localizable",
      bundle: CarPlayL10n.bundle)
  }

  // MARK: - Clock

  /// Minutes since midnight in the day's timezone, the clock the rows are read
  /// against. `nil` until the first refresh.
  public var nowMinutes: Int? {
    guard let timezone = dayTimezone else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let date = now()
    return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
  }

  /// The day's timezone as of the last refresh: the schedule's, else Today's
  /// product timezone. `nil` until the first refresh.
  public private(set) var dayTimezone: TimeZone?

  /// The wall clock the rows are read against. Injectable so tests and
  /// previews can pin the time of day.
  public var now: @Sendable () -> Date

  // MARK: - Rows

  /// The car list, top to bottom: Today's tasks with the ``TodayLead`` first
  /// when one leads (a running saved time, else a started task, else the next
  /// saved time), read against the clock; otherwise Today's order.
  public var rows: [Row] {
    TodayLead.ordered(
      todayRows, nowMinutes: nowMinutes,
      time: { row in
        guard let start = row.startMinutes, let end = row.endMinutes, end > start else {
          return nil
        }
        return start..<end
      },
      isStarted: \.isStarted)
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

  /// - Parameters:
  ///   - core: The service to load tasks from. Defaults to the mobile HLC
  ///     surface when nil.
  ///   - now: The wall clock, injectable so tests can pin the time of day.
  public init(core: (any LorvexCoreServicing)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
    self.core = core ?? LorvexCoreRuntimeFactory.makeForMobile()
    self.now = now
  }

  // MARK: - Public API

  /// Loads Today's list, each task carrying its time today, then updates
  /// `todayRows`. Throws if the read fails.
  public func refresh() async throws {
    let today = try await core.loadToday()
    let logicalDay: String
    if let day = today.logicalDay {
      logicalDay = day
    } else {
      logicalDay = try await core.getSessionContext().date
    }
    dayTimezone = today.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
    todayRows = today.tasks.map { task in
      let time = task.time(on: logicalDay)
      return Self.row(
        for: task, logicalDay: logicalDay,
        startMinutes: time?.lowerBound, endMinutes: time?.upperBound)
    }
  }

  /// Completes the task with the given `id` and refreshes the list.
  /// Throws if the task is not found or the service call fails.
  public func complete(id: String) async throws {
    _ = try await core.completeTask(id: id)
    try await refresh()
  }

  /// Defers the task with the given `id` to tomorrow in the configured product
  /// timezone, stored at the UTC-anchored planned-day instant, and refreshes the
  /// list. The task drops out of Today until tomorrow.
  /// Throws if the task is not found or the service call fails.
  public func deferToTomorrow(id: String) async throws {
    let logicalDay = try await core.getSessionContext().date
    _ = try await core.deferTask(id: id, until: Self.tomorrowDate(after: logicalDay))
    try await refresh()
  }

  // MARK: - Internal

  /// A task as a car-screen row. Overdue means the due day lies before the
  /// logical day; both are `yyyy-MM-dd` day keys in the storage frame.
  private static func row(
    for task: LorvexTask, logicalDay: String, startMinutes: Int?, endMinutes: Int?
  ) -> Row {
    let dueDay = task.dueDate.map { LorvexDateFormatters.ymdUTC.string(from: $0) }
    return Row(
      id: task.id, title: task.title,
      startMinutes: startMinutes, endMinutes: endMinutes,
      estimatedMinutes: task.estimatedMinutes,
      isStarted: task.status == .inProgress,
      isOverdue: dueDay.map { $0 < logicalDay } ?? false)
  }
}
