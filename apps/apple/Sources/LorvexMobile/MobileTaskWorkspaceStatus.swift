import Foundation
import LorvexCore

enum MobileTaskWorkspaceStatus: String, CaseIterable, Identifiable, Sendable {
  case open
  case someday
  case completed
  case cancelled

  var id: String { rawValue }

  var emptyTitle: String {
    switch self {
    case .open:
      String(
        localized: "tasks.empty.open.title", defaultValue: "No Open Tasks", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .someday:
      String(
        localized: "tasks.empty.someday.title", defaultValue: "No Someday Tasks",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .completed:
      String(
        localized: "tasks.empty.completed.title", defaultValue: "No Completed Tasks",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .cancelled:
      String(
        localized: "tasks.empty.cancelled.title", defaultValue: "No Cancelled Tasks",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  var emptyMessage: String {
    switch self {
    case .open:
      String(
        localized: "tasks.empty.open.message",
        defaultValue: "Capture a task or ask the assistant to plan the next useful work.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .someday:
      String(
        localized: "tasks.empty.someday.message",
        defaultValue: "Someday tasks are parked commitments that should not distract today.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .completed:
      String(
        localized: "tasks.empty.completed.message",
        defaultValue: "Completed tasks will appear here after work is closed out.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .cancelled:
      String(
        localized: "tasks.empty.cancelled.message",
        defaultValue: "Cancelled tasks stay here, so you can look back on past decisions.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// The core task status this lane filters on. Every mobile lane maps 1:1 to a
  /// `LorvexTask.Status` (the mobile workspace has no date-derived lanes).
  var taskStatus: LorvexTask.Status {
    switch self {
    case .open: .open
    case .someday: .someday
    case .completed: .completed
    case .cancelled: .cancelled
    }
  }

  /// Status string for `list_tasks` / `search_tasks`. The Open lane queries the
  /// `actionable` working set so a started (in_progress) task shows there
  /// instead of vanishing; the other lanes bind their exact status.
  var coreStatus: String {
    switch self {
    case .open:
      return LorvexTask.Status.actionableFilter
    case .someday, .completed, .cancelled:
      return LorvexTask.Status.coreQueryString(for: taskStatus)
    }
  }

  func includes(_ task: LorvexTask) -> Bool {
    switch self {
    case .open:
      return task.status.isActionable
    case .someday, .completed, .cancelled:
      return task.status == taskStatus
    }
  }
}

struct MobileTaskWorkspacePage: Equatable, Sendable {
  var tasks: [LorvexTask]
  var totalMatching: Int
  var nextOffset: Int?
  /// True when the scope narrows the raw status/list query in memory, so each
  /// page's `totalMatching` is only that page's post-filter count rather than a
  /// stable global total. Governs how ``appending(_:)`` combines the counts.
  var isNarrowed: Bool = false
  /// The ids of the page's tasks that wait on an unfinished task, read with
  /// the page (``LorvexTaskServicing/blockedTaskIDs(in:)``): their rows show
  /// Blocked and offer no Start.
  var blockedTaskIDs: Set<LorvexTask.ID> = []

  static let empty = MobileTaskWorkspacePage(tasks: [], totalMatching: 0, nextOffset: nil)

  func appending(_ page: MobileTaskWorkspacePage) -> MobileTaskWorkspacePage {
    // Non-narrowing scopes carry the same global DB total on every page, so
    // keeping the newest page's `totalMatching` is correct. Narrowing scopes
    // carry only a per-page filtered count; last-wins would make the header
    // read the last page's slice (e.g. "30 tasks" over 70 visible rows) and
    // even decrease as more loads. Summing yields the rows loaded so far — the
    // honest count for a narrowed set whose true corpus total is unknown without
    // scanning every window.
    let narrowed = isNarrowed || page.isNarrowed
    return MobileTaskWorkspacePage(
      tasks: tasks + page.tasks,
      totalMatching: narrowed ? totalMatching + page.totalMatching : page.totalMatching,
      nextOffset: page.nextOffset,
      isNarrowed: narrowed,
      blockedTaskIDs: blockedTaskIDs.union(page.blockedTaskIDs)
    )
  }
}
