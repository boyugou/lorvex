import LorvexCore
import SwiftUI

/// The Calendar's "Unplanned Tasks" rail: the open tasks that have no planned
/// day, in the canonical task order, beside the grid. Each row drags by id, so a
/// task goes from here onto a time in a day column, a day's all-day strip, or a
/// month cell without leaving the calendar; planning it removes it from the
/// rail. A row opens its task on a click, Return, or Space and carries the same
/// context menu as every other task list. Its metadata line leaves out the
/// owning list, so the due day and the estimate, which decide where a task goes,
/// never get cut off in the narrow column.
///
/// The rail lists the first ``AppStore/calendarUnplannedLimit`` tasks and ends
/// with "N more" when there are others. It is empty only when every open task
/// has a day.
struct CalendarPlanRail: View {
  @Bindable var store: AppStore
  let openTask: (LorvexTask) -> Void

  static let width: CGFloat = 280

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      if let tasks = store.calendarUnplannedTasks {
        if tasks.isEmpty {
          emptyState
        } else {
          list(tasks)
        }
      } else {
        Spacer(minLength: 0)
      }
    }
    .frame(width: Self.width)
    .frame(maxHeight: .infinity, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(CalendarPlanRailCopy.title)
    .accessibilityIdentifier("calendar.planRail")
  }

  /// The title band on the shared bar chrome. It reserves the line height of a
  /// workspace's large title, so its divider meets the Calendar header's across
  /// the window.
  private var header: some View {
    WorkspaceReviewHeaderChrome {
      ZStack(alignment: .leading) {
        Text(verbatim: " ")
          .font(LorvexDesign.Typography.screenTitle)
          .hidden()
        HStack(alignment: .firstTextBaseline) {
          Text(CalendarPlanRailCopy.title)
            .font(LorvexDesign.Typography.primaryEmphasis)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
          Spacer(minLength: LorvexDesign.Spacing.s)
          if store.calendarUnplannedTotal > 0 {
            Text(store.calendarUnplannedTotal.formatted(.number.locale(LorvexClockFormat.displayLocale)))
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("calendar.planRail.count")
          }
        }
      }
    }
  }

  private func list(_ tasks: [LorvexTask]) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        Text(CalendarPlanRailCopy.hint)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, LorvexDesign.Spacing.m)
          .padding(.vertical, LorvexDesign.Spacing.s)
        ForEach(tasks) { task in
          row(task)
        }
        let hidden = store.calendarUnplannedTotal - tasks.count
        if hidden > 0 {
          Text(ReviewCalmCopy.moreCount(hidden))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .padding(.horizontal, LorvexDesign.Spacing.m)
            .padding(.vertical, LorvexDesign.Spacing.s)
            .accessibilityIdentifier("calendar.planRail.more")
        }
      }
      .padding(.horizontal, LorvexDesign.Spacing.xs)
      .padding(.vertical, LorvexDesign.Spacing.xs)
    }
  }

  private func row(_ task: LorvexTask) -> some View {
    TaskRowItem(store: store, task: task)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .onTapGesture {
        if store.selectedTaskID == task.id {
          store.selectedTaskID = nil
        } else {
          openTask(task)
        }
      }
      .lorvexKeyboardActivation { openTask(task) }
      .accessibilityAction(.default) { openTask(task) }
      .contextMenu { WorkspaceTaskContextMenu(store: store, task: task) }
  }

  private var emptyState: some View {
    VStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "checkmark.circle")
        .font(.title2)
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      Text(CalendarPlanRailCopy.empty)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("calendar.planRail.empty")
  }
}

/// The rail's own text. The title also names the toolbar button that shows and
/// hides it.
enum CalendarPlanRailCopy {
  static var title: String {
    String(
      localized: "calendar.plan_rail.title", defaultValue: "Unplanned Tasks",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var hint: String {
    String(
      localized: "calendar.plan_rail.hint",
      defaultValue: "Drag a task onto a day or a time to plan it.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  static var empty: String {
    String(
      localized: "calendar.plan_rail.empty", defaultValue: "All tasks are planned.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
