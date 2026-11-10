import Foundation
import LorvexCore

/// Brings the App Group snapshot forward to the current logical day before a
/// widget timeline or a Control Center value is built from it.
///
/// The app writes the snapshot, and an iPhone app is suspended at midnight, so
/// a widget that reloads at the day boundary finds yesterday's file, which it
/// must not present as today. When the file decodes but belongs to an earlier
/// logical day, ``rollOverIfExpired(snapshotURL:)`` rebuilds it from the shared
/// database — the read and write an interactive widget intent makes after a
/// tap — so the reload shows the new day instead of "Open Lorvex to refresh".
///
/// Only an expired day triggers the rebuild. A missing file can mean the app has
/// never run, and an extension must not be the first process to open the
/// managed store; an unreadable, damaged, or newer-version file is likewise left
/// for the app. A rebuild that fails, or that still yields an earlier day,
/// leaves the caller reading what it would have read anyway: the expired-day
/// fallback, with its usual retry interval.
public struct WidgetSnapshotDayRollover: Sendable {
  private let freshnessPolicy: WidgetSnapshotFreshnessPolicy
  private let calendar: Calendar
  private let now: @Sendable () -> Date
  private let rebuild: @Sendable (URL) async throws -> Void

  /// `rebuild` writes a current snapshot to the URL it is given; `now` and
  /// `calendar` decide whether the file on disk is for an earlier day, as the
  /// timeline providers do.
  public init(
    freshnessPolicy: WidgetSnapshotFreshnessPolicy = WidgetSnapshotFreshnessPolicy(),
    calendar: Calendar = .autoupdatingCurrent,
    now: @escaping @Sendable () -> Date = Date.init,
    rebuild: @escaping @Sendable (URL) async throws -> Void
  ) {
    self.freshnessPolicy = freshnessPolicy
    self.calendar = calendar
    self.now = now
    self.rebuild = rebuild
  }

  /// The widget extension's rollover: one atomic read of the managed store
  /// through the widget surface's core service, projected and written by
  /// ``WidgetSnapshotLiveRefresher``. It reloads no timeline: the surface that
  /// asked is building its own from the rebuilt file, and every other surface
  /// rolls itself over when it next reloads, so a reload here would only spend
  /// the widgets' daily budget.
  public static let live = WidgetSnapshotDayRollover(rebuild: { snapshotURL in
    let core = LorvexCoreRuntimeFactory.makeForWidget()
    _ = try await WidgetSnapshotLiveRefresher.live(reloadTimelines: {})
      .refresh(core: core, snapshotURL: snapshotURL)
  })

  /// Rebuilds the snapshot at `snapshotURL` when it belongs to an earlier
  /// logical day, and returns whether a rebuild completed. Any other file, a
  /// nil URL, or a rebuild that throws leaves everything as it was.
  @discardableResult
  public func rollOverIfExpired(snapshotURL: URL?) async -> Bool {
    guard let snapshotURL else { return false }
    let result = freshnessPolicy.validatingCurrentDay(
      WidgetSnapshotLoader().loadSnapshot(at: snapshotURL), now: now(), calendar: calendar)
    guard case .fallback(let fallback) = result, fallback.reason == .expiredDay else {
      return false
    }
    do {
      try await rebuild(snapshotURL)
      return true
    } catch {
      return false
    }
  }
}
