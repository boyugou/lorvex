import LorvexCore
import SwiftUI

/// The calm Today plan header: the day's title and one today-scoped digest
/// ("N to do · N focused" with an overdue capsule). The total open-task count
/// belongs to the Tasks queue, not here, so Today shows only the counts that
/// describe today. `trailingActions` carries the focus-plan schedule controls
/// (Propose / Save / Clear), supplied by `TodayView`, which owns the clear
/// confirmation dialog and the working-hours tooltip text.
struct TodayHeaderView<TrailingActions: View>: View {
  @Bindable var store: AppStore
  @ViewBuilder let trailingActions: () -> TrailingActions

  var body: some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.m) {
          WorkspaceHeaderIdentity(
            // The page identity, not `today.focusTitle`: the production core
            // returns a fixed English "Today" in that field, which rendered an
            // unlocalized title (and duplicated the window title verbatim).
            title: String(
              localized: "sidebar.item.today", defaultValue: "Today", table: "Localizable",
              bundle: LorvexL10n.bundle),
            subtitle: subtitle,
            systemImage: SidebarSelection.today.systemImage,
            accessibilityIdentifier: "today.header.identity",
            subtitleAccessibilityIdentifier: "today-header-subtitle"
          )

          Spacer(minLength: LorvexDesign.Spacing.m)

          trailingActions()
        }

        TodayHeaderSignals(
          digestText: digestText,
          overdueCount: overdueCount,
          isAllClear: todoCount == 0
        )
      }
    }
  }

  private var subtitle: String {
    String(
      localized: "sidebar.detail.today", defaultValue: "Daily plan", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// "8 to do · 2 focused" — derived from the visible partitions so it always
  /// matches the list below; "All clear for today" when nothing is scheduled.
  /// Focused tasks are a subset of the to-do total, so the second clause reads
  /// as a highlight rather than an additional bucket.
  private var digestText: String {
    guard todoCount > 0 else {
      return String(
        localized: "today.header.all_clear", defaultValue: "All clear for today",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    let todoText = String(
      format: String(
        localized: "today.header.todo_count", defaultValue: "%lld to do",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      todoCount)
    var parts = [todoText]
    if focusedCount > 0 {
      let focusedText = String(
        format: String(
          localized: "today.header.focused_count", defaultValue: "%lld focused",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        focusedCount)
      parts.append(focusedText)
    }
    return parts.joined(separator: " · ")
  }

  private var todoCount: Int {
    store.focusSurfaceOrderedTasks.count
  }

  private var focusedCount: Int {
    store.filteredFocusedTasks.count
  }

  private var overdueCount: Int {
    store.focusSurfaceOrderedTasks.filter { $0.isOverdue() }.count
  }
}

private struct TodayHeaderSignals: View {
  let digestText: String
  let overdueCount: Int
  let isAllClear: Bool

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
        digestRow
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        digestRow
      }
    }
  }

  private var digestRow: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Label(digestText, systemImage: isAllClear ? "sparkles" : "checklist")
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)

      if overdueCount > 0 {
        Text(overdueText)
          .foregroundStyle(.orange)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(.orange.opacity(0.10), in: Capsule())
      }
    }
    .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.header.digest")
  }

  private var overdueText: String {
    String(
      format: String(
        localized: "today.header.overdue_count", defaultValue: "%lld overdue",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      overdueCount)
  }
}
