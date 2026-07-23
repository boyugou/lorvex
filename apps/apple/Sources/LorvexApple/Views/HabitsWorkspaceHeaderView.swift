import LorvexCore
import SwiftUI

struct HabitsWorkspaceHeader: View {
  let summary: String
  let stats: HabitsWorkspaceStats
  let create: () -> Void

  var body: some View {
    WorkspaceDashboardHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
          WorkspaceHeaderIdentity(
            title: String(localized: "sidebar.item.habits", defaultValue: "Habits", table: "Localizable", bundle: LorvexL10n.bundle),
            subtitle: summary,
            systemImage: SidebarSelection.habits.systemImage,
            accessibilityIdentifier: "habits.header.identity",
            subtitleAccessibilityIdentifier: "habits.header.summary"
          )
          Spacer(minLength: LorvexDesign.Spacing.m)
          Button(action: create) {
            Image(systemName: "plus")
          }
          .buttonStyle(.lorvexNeutral)
          .help(String(localized: "habits.workspace.create_help", defaultValue: "Create Habit", table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityLabel(String(localized: "habits.workspace.create_a11y", defaultValue: "Create Habit", table: "Localizable", bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("habits.create")
          .fixedSize()
        }

        if stats.hasHabits {
          heroBand
        }
      }
    }
  }

  /// A momentum band broken out by cadence: today's daily completion, this
  /// week's weekly completion, this month's monthly completion — each shown only
  /// when that cadence has habits, since a weekly/monthly habit isn't "today's"
  /// task. Best streak trails.
  private var heroBand: some View {
    HStack(spacing: LorvexDesign.Spacing.l) {
      ForEach(stats.buckets, id: \.cadence) { bucket in
        heroStat(
          value: "\(bucket.completed)/\(bucket.total)",
          label: Self.bucketLabel(bucket.cadence),
          systemImage: Self.bucketIcon(bucket.cadence),
          tint: bucket.isComplete ? .green : .secondary)
      }
      heroStat(
        value: lorvexDaysLabel(stats.bestStreak),
        label: String(localized: "habits.header.stat.best_streak", defaultValue: "Best streak", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "flame.fill", tint: stats.bestStreak > 0 ? .orange : .secondary)

      Spacer(minLength: 0)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .accessibilityIdentifier("habits.header.stats")
  }

  private func heroStat(value: String, label: String, systemImage: String, tint: Color) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(tint)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(value)
          .font(LorvexDesign.Typography.primaryEmphasis.monospacedDigit())
        Text(label)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
    }
  }

  private static func bucketLabel(_ bucket: HabitCadenceBucket) -> String {
    switch bucket {
    case .daily:
      String(localized: "habits.header.cadence.daily", defaultValue: "Daily · today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weekly:
      String(localized: "habits.header.cadence.weekly", defaultValue: "Weekly · this week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .monthly:
      String(localized: "habits.header.cadence.monthly", defaultValue: "Monthly · this month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private static func bucketIcon(_ bucket: HabitCadenceBucket) -> String {
    switch bucket {
    case .daily: "sun.max"
    case .weekly: "calendar"
    case .monthly: "calendar.badge.clock"
    }
  }
}

/// The habit board's header stats, broken out per cadence bucket so each rhythm
/// is counted against its own period (today / this week / this month).
struct HabitsWorkspaceStats: Equatable {
  struct Bucket: Equatable {
    let cadence: HabitCadenceBucket
    let completed: Int
    let total: Int
    var isComplete: Bool { total > 0 && completed >= total }
  }

  let buckets: [Bucket]
  let bestStreak: Int

  var hasHabits: Bool { buckets.contains { $0.total > 0 } }
}
