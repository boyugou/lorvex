import LorvexCore
import SwiftUI

/// The Habits board header: the identity and one line under it saying how
/// many habits are done in each period that has any ("1 of 2 done today · 2
/// of 3 done this week"). Each cadence counts against its own period, since a
/// weekly habit is not today's task. An empty board shows the title alone,
/// since the empty-state panel below already speaks for it. The create action
/// rides in the window toolbar (`HabitsWorkspaceView`).
struct HabitsWorkspaceHeader: View {
  let stats: HabitsWorkspaceStats

  var body: some View {
    WorkspaceDashboardHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: "sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: subtitle,
        icon: SidebarSelection.habits.systemImage,
        accessibilityIdentifier: "habits.header.identity",
        subtitleAccessibilityIdentifier: "habits.header.summary"
      )
    }
  }

  private var subtitle: String {
    stats.buckets.map(Self.progress).joined(separator: " · ")
  }

  private static func progress(_ bucket: HabitsWorkspaceStats.Bucket) -> String {
    let (done, total) = (bucket.completed, bucket.total)
    return switch bucket.cadence {
    case .daily:
      String(
        localized: "habits.header.done.today", defaultValue: "\(done) of \(total) done today",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .weekly:
      String(
        localized: "habits.header.done.week", defaultValue: "\(done) of \(total) done this week",
        table: "Localizable", bundle: LorvexL10n.bundle)
    case .monthly:
      String(
        localized: "habits.header.done.month", defaultValue: "\(done) of \(total) done this month",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

/// How many of the board's habits meet their current period's plan, per
/// cadence bucket that has any habits, each counted against its own period
/// (today / this week / this month).
struct HabitsWorkspaceStats: Equatable {
  struct Bucket: Equatable {
    let cadence: HabitCadenceBucket
    let completed: Int
    let total: Int
  }

  let buckets: [Bucket]
}
