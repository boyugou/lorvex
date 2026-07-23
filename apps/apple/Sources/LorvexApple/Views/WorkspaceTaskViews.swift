import LorvexCore
import SwiftUI

private enum WorkspaceTaskSectionMetrics {
  static let iconWidth: CGFloat = 16
  static let countHorizontalPadding: CGFloat = 6
  static let countVerticalPadding: CGFloat = 1
}

private enum WorkspaceTaskSectionTypography {
  /// Top-level group titles (Next Up, Later, History) — deliberately larger than
  /// the sub-section titles so the two tiers read as a hierarchy.
  static let title = LorvexDesign.Typography.primaryText.weight(.semibold)
  /// Sub-section titles nested under a top-level group (Completed / Cancelled
  /// under History, Someday under Later) — smaller and muted.
  static let subtitle = LorvexDesign.Typography.tertiaryText.weight(.semibold)
  static let icon = LorvexDesign.Typography.tertiaryText.weight(.semibold)
  static let count = LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium)
}

struct WorkspaceTaskSectionHeader: View {
  let title: String
  let countText: String
  let systemImage: String
  let tint: Color
  var topSpacing: CGFloat = LorvexDesign.Spacing.m
  var bottomSpacing: CGFloat = LorvexDesign.Spacing.xs
  /// A header for a section nested under a top-level group (e.g. Completed under
  /// History) — rendered smaller and muted so it reads as subordinate.
  var isSubsection: Bool = false

  init(
    title: String,
    count: Int,
    systemImage: String,
    tint: Color,
    topSpacing: CGFloat = LorvexDesign.Spacing.m,
    bottomSpacing: CGFloat = LorvexDesign.Spacing.xs,
    isSubsection: Bool = false
  ) {
    self.title = title
    self.countText = "\(count)"
    self.systemImage = systemImage
    self.tint = tint
    self.topSpacing = topSpacing
    self.bottomSpacing = bottomSpacing
    self.isSubsection = isSubsection
  }

  init(
    title: String,
    countText: String,
    systemImage: String,
    tint: Color,
    topSpacing: CGFloat = LorvexDesign.Spacing.m,
    bottomSpacing: CGFloat = LorvexDesign.Spacing.xs,
    isSubsection: Bool = false
  ) {
    self.title = title
    self.countText = countText
    self.systemImage = systemImage
    self.tint = tint
    self.topSpacing = topSpacing
    self.bottomSpacing = bottomSpacing
    self.isSubsection = isSubsection
  }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .font(WorkspaceTaskSectionTypography.icon)
        .foregroundStyle(tint)
        .frame(width: WorkspaceTaskSectionMetrics.iconWidth)

      Text(title)
        .font(isSubsection
          ? WorkspaceTaskSectionTypography.subtitle
          : WorkspaceTaskSectionTypography.title)
        .foregroundStyle(isSubsection ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

      WorkspaceTaskSectionCountBadge(countText: countText)

      Spacer(minLength: 0)
    }
    .textCase(nil)
    .padding(.top, topSpacing)
    .padding(.bottom, bottomSpacing)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(lorvexPairLabel(title, countText))
    .accessibilityAddTraits(.isHeader)
  }
}

struct WorkspaceTaskDisclosureHeader: View {
  @Binding var isExpanded: Bool
  let title: String
  let countText: String
  let systemImage: String
  let tint: Color

  var body: some View {
    Button {
      lorvexAnimated(.snappy(duration: 0.16)) {
        isExpanded.toggle()
      }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: systemImage)
          .font(WorkspaceTaskSectionTypography.icon)
          .foregroundStyle(tint)
          .frame(width: WorkspaceTaskSectionMetrics.iconWidth)

        Text(title)
          .font(WorkspaceTaskSectionTypography.title)
          .foregroundStyle(.secondary)

        WorkspaceTaskSectionCountBadge(countText: countText)

        Spacer(minLength: 0)

        Image(systemName: "chevron.right")
          .font(WorkspaceTaskSectionTypography.icon)
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .frame(width: WorkspaceTaskSectionMetrics.iconWidth)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(lorvexPairLabel(title, countText))
    .accessibilityValue(
      isExpanded
        ? Text(LocalizedStringResource("common.expanded", defaultValue: "Expanded", table: "Localizable", bundle: LorvexL10n.bundle))
        : Text(LocalizedStringResource("common.collapsed", defaultValue: "Collapsed", table: "Localizable", bundle: LorvexL10n.bundle))
    )
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier("workspace.task.disclosureHeader")
  }
}

private struct WorkspaceTaskSectionCountBadge: View {
  let countText: String

  var body: some View {
    Text(countText)
      .font(WorkspaceTaskSectionTypography.count)
      .foregroundStyle(.secondary)
      .padding(.horizontal, WorkspaceTaskSectionMetrics.countHorizontalPadding)
      .padding(.vertical, WorkspaceTaskSectionMetrics.countVerticalPadding)
      .background(.quaternary.opacity(0.42), in: Capsule())
      .overlay {
        Capsule()
          .stroke(.quaternary.opacity(0.55), lineWidth: 0.5)
      }
  }
}

struct WorkspaceTaskContextMenu: View {
  @Bindable var store: AppStore
  let task: LorvexTask
  @Environment(\.undoManager) private var undoManager
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    let isFocused = store.focusedTaskIDSet.contains(task.id)
    Button {
      store.selectedTaskID = task.id
      Task { await store.toggleSelectedTaskFocus() }
    } label: {
      Label(
        isFocused
          ? String(
            localized:
              "workspace.task.remove_from_focus",
              defaultValue: "Remove from Focus",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            )
          : String(
            localized:
              "workspace.task.add_to_focus",
              defaultValue: "Add to Focus",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
        systemImage: isFocused ? "minus.circle" : "scope"
      )
    }

    TaskDeferMenu(store: store, onDefer: { date in
      Task { await store.deferTaskFromRow(task, until: date) }
    }) {
      Label(
        String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "clock.arrow.circlepath"
      )
    }
    .disabled(task.status.isResolved)

    TaskSnoozeMenu(store: store, onSnooze: { date in
      Task { await store.snoozeTask(id: task.id, until: date) }
    }) {
      Label(
        String(localized: "task.snooze.title", defaultValue: "Snooze Until", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "eye.slash"
      )
    }
    .disabled(task.status.isResolved)
    .accessibilityIdentifier("task.snooze.\(task.id)")

    Button {
      store.selectedTaskID = task.id
      Task { await store.completeSelectedTask(undoManager: undoManager) }
    } label: {
      Label(
        String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checkmark.circle"
      )
    }
    .disabled(task.status.isResolved)

    if task.status == .inProgress {
      Button {
        store.selectedTaskID = task.id
        Task { await store.markSelectedTaskNotStarted() }
      } label: {
        Label(
          String(
            localized: "task.action.mark_not_started", defaultValue: "Mark as Not Started",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "pause.circle"
        )
      }
    } else {
      Button {
        store.selectedTaskID = task.id
        Task { await store.startSelectedTask() }
      } label: {
        Label(
          String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "play.circle"
        )
      }
      .disabled(task.status != .open)
    }

    Button {
      store.selectedTaskID = task.id
      Task { await store.reopenSelectedTask() }
    } label: {
      Label(
        String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "arrow.counterclockwise"
      )
    }
    .disabled(!(task.status.isResolved))

    if task.status == .someday {
      Button {
        store.selectedTaskID = task.id
        Task { await store.reopenSelectedTask() }
      } label: {
        Label(
          String(localized: "task.action.move_to_open", defaultValue: "Move to Open", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.circle"
        )
      }
    } else {
      Button {
        store.selectedTaskID = task.id
        Task { await store.markSelectedTaskSomeday() }
      } label: {
        Label(
          String(localized: "task.action.move_to_someday", defaultValue: "Move to Someday", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "moon"
        )
      }
      .disabled(task.status != .open)
    }

    Divider()

    Button {
      openWindow(id: LorvexWindowID.stickyTaskGroupID, value: StickyTaskRef(taskID: task.id))
    } label: {
      Label(
        String(localized: "task_detail.pin_sticky", defaultValue: "Pin as Sticky", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "pin"
      )
    }

    Button(role: .destructive) {
      // Recurring tasks route to the shared occurrence-vs-series scope dialog
      // (ContentView); non-recurring cancel directly. Matches the detail pane.
      store.requestCancel(task, undoManager: undoManager)
    } label: {
      Label(
        String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "xmark.circle"
      )
    }
    .disabled(task.status.isResolved)

    Button(role: .destructive) {
      store.selectedTaskID = task.id
      store.requestPermanentDelete(task)
    } label: {
      Label(
        String(localized: "task.permanent_delete.action", defaultValue: "Delete Permanently…", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "trash"
      )
    }
  }
}
