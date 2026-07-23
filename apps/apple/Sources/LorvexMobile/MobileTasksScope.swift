import LorvexCore
import SwiftUI

/// What slice of the task corpus the Tasks workspace is showing. The Tasks tab
/// is a home of smart collections + lists; drilling into any of them pushes the
/// workspace scoped to one of these.
public enum MobileTasksScope: Hashable, Sendable {
  /// All open tasks.
  case all
  /// Open tasks that carry a due date.
  case scheduled
  /// Open top-priority tasks.
  case priority
  /// Parked "someday" tasks.
  case someday
  /// Resolved (completed) tasks, for review.
  case completed
  /// Cancelled tasks, kept inspectable so old decisions stay reviewable.
  case cancelled
  /// Open tasks in a specific list.
  case list(LorvexList.ID)

  /// The underlying status filter this scope queries (and the empty-state copy
  /// it borrows).
  var baseStatus: MobileTaskWorkspaceStatus {
    switch self {
    case .all, .scheduled, .priority, .list: .open
    case .someday: .someday
    case .completed: .completed
    case .cancelled: .cancelled
    }
  }

  /// The list filter, when scoped to a single list.
  var listID: LorvexList.ID? {
    if case .list(let id) = self { return id }
    return nil
  }

  /// An extra in-memory predicate beyond the status/list query (the cross-list
  /// smart cuts the core query can't express directly).
  func matches(_ task: LorvexTask) -> Bool {
    switch self {
    case .scheduled: return task.dueDate != nil
    case .priority: return task.priority == .p1
    default: return true
    }
  }

  /// Whether the scope filters in memory beyond the status/list query, so the
  /// page total should reflect the filtered page rather than the raw query total.
  var narrowsInMemory: Bool {
    switch self {
    case .scheduled, .priority, .list: true
    case .all, .someday, .completed, .cancelled: false
    }
  }

  /// The navigation-title name for this scope. For a list, resolves the live
  /// list name from the store (falling back to "Lists").
  @MainActor
  func displayTitle(store: MobileStore) -> String {
    switch self {
    case .all:
      String(
        localized: "tasks.scope.all", defaultValue: "All", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .scheduled:
      String(
        localized: "tasks.scope.scheduled", defaultValue: "Scheduled", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .priority:
      String(
        localized: "tasks.scope.priority", defaultValue: "Priority", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .someday:
      String(
        localized: "tasks.scope.someday", defaultValue: "Someday", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .completed:
      String(
        localized: "tasks.scope.completed", defaultValue: "Completed", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .cancelled:
      String(
        localized: "tasks.scope.cancelled", defaultValue: "Cancelled", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .list(let id):
      store.lists?.lists.first(where: { $0.id == id })?.name
        ?? String(
          localized: "destination.lists", defaultValue: "Lists", table: "Localizable",
          bundle: MobileL10n.bundle)
    }
  }
}

/// A smart collection card on the Tasks home (a fixed, cross-list cut).
struct MobileTaskSmartCollection: Identifiable {
  let scope: MobileTasksScope
  let title: String
  let systemImage: String
  let tint: Color
  var id: String { title }

  /// The 2×2 grid shown above "My Lists".
  static let grid: [MobileTaskSmartCollection] = [
    .init(
      scope: .all,
      title: String(
        localized: "tasks.scope.all", defaultValue: "All", table: "Localizable",
        bundle: MobileL10n.bundle),
      systemImage: "tray.full.fill", tint: .blue),
    .init(
      scope: .scheduled,
      title: String(
        localized: "tasks.scope.scheduled", defaultValue: "Scheduled", table: "Localizable",
        bundle: MobileL10n.bundle),
      systemImage: "calendar", tint: .red),
    .init(
      scope: .priority,
      title: String(
        localized: "tasks.scope.priority", defaultValue: "Priority", table: "Localizable",
        bundle: MobileL10n.bundle),
      systemImage: "flag.fill", tint: .orange),
    .init(
      scope: .someday,
      title: String(
        localized: "tasks.scope.someday", defaultValue: "Someday", table: "Localizable",
        bundle: MobileL10n.bundle),
      systemImage: "moon.stars.fill", tint: .indigo),
  ]
}
