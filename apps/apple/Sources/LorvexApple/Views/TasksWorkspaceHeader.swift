import LorvexCore
import SwiftUI

struct TasksWorkspaceHeader: View {
  @Bindable var store: AppStore
  let title: String
  let subtitle: String
  let scope: TasksHeaderScope?
  let summary: String?
  let metrics: [TasksHeaderMetric]
  @Binding var isTableMode: Bool
  @Binding var priorityFilter: LorvexTask.Priority?

  var body: some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
          WorkspaceHeaderIdentity(
            title: title,
            subtitle: subtitle,
            systemImage: SidebarSelection.tasks.systemImage,
            accessibilityIdentifier: "tasks.header.identity"
          ) {
            if let scope {
              TasksHeaderScopeBadge(scope: scope) {
                store.setTaskWorkspaceListScope(nil)
              }
            }
          }

          Spacer(minLength: LorvexDesign.Spacing.m)

          TasksHeaderActions(
            store: store,
            isTableMode: $isTableMode,
            priorityFilter: $priorityFilter
          )
        }

        TasksHeaderContextRow(
          metrics: metrics,
          summary: summary
        )
      }
    }
  }
}

struct TasksHeaderMetric {
  let title: String
  let count: Int
  let tint: Color
  var isAttention = false
}

struct TasksHeaderScope {
  let name: String
  let icon: String?
  let tint: Color
}

private struct TasksHeaderContextRow: View {
  let metrics: [TasksHeaderMetric]
  let summary: String?

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
        digestRow
        summaryText
        Spacer(minLength: 0)
      }

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
          digestRow
          summaryText
        }
      }
    }
    .accessibilityIdentifier("tasks.header.contextRow")
  }

  @ViewBuilder
  private var digestRow: some View {
    if !metrics.isEmpty {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Label(metricsDigestText, systemImage: "checklist")
          .labelStyle(.titleAndIcon)
          .foregroundStyle(.secondary)

        if let attentionMetric {
          Text(metricText(attentionMetric))
            .foregroundStyle(attentionMetric.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(attentionMetric.tint.opacity(0.10), in: Capsule())
        }
      }
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("tasks.header.digest")
    }
  }

  private var normalMetrics: [TasksHeaderMetric] {
    metrics.filter { !$0.isAttention }
  }

  private var attentionMetric: TasksHeaderMetric? {
    metrics.first { $0.isAttention }
  }

  private var metricsDigestText: String {
    let displayMetrics = normalMetrics.isEmpty ? metrics : normalMetrics
    return displayMetrics.map(metricText).joined(separator: " · ")
  }

  private func metricText(_ metric: TasksHeaderMetric) -> String {
    "\(metric.count) \(metric.title.localizedLowercase)"
  }

  @ViewBuilder
  private var summaryText: some View {
    if let summary, !summary.isEmpty {
      WorkspaceHeaderSummary(
        text: summary,
        accessibilityIdentifier: "tasks.header.summary",
        tone: .secondary,
        lineLimit: 1,
        expandsVertically: false
      )
    }
  }
}

private struct TasksHeaderScopeBadge: View {
  let scope: TasksHeaderScope
  let clearScope: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      LorvexListIconView(
        icon: scope.icon,
        tint: scope.tint,
        size: 16,
        font: LorvexDesign.Typography.tertiaryText.weight(.medium)
      )

      Text(scope.name)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.tail)

      Button(action: clearScope) {
        Image(systemName: "xmark.circle.fill")
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
          .foregroundStyle(.tertiary)
          .frame(width: 14, height: 14)
      }
      .buttonStyle(.plain)
      .help(String(
        localized: "tasks.header.scope.clear",
        defaultValue: "Show All Tasks",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .accessibilityLabel(String(
        localized: "tasks.header.scope.clear",
        defaultValue: "Show All Tasks",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
      .accessibilityIdentifier("tasks.header.clearScope")
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, 3)
    .frame(maxWidth: 180, alignment: .leading)
    .background(scope.tint.opacity(0.10), in: Capsule())
    .overlay {
      Capsule()
        .stroke(scope.tint.opacity(0.18), lineWidth: 0.5)
    }
    .accessibilityIdentifier("tasks.header.scope")
  }
}

private struct TasksHeaderActions: View {
  @Bindable var store: AppStore
  @Binding var isTableMode: Bool
  @Binding var priorityFilter: LorvexTask.Priority?

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if store.taskWorkspaceSelectionCount > 1 {
        TasksSelectionActionMenu(store: store)
      }

      TasksReviewOptionsMenu(
        isTableMode: $isTableMode,
        priorityFilter: $priorityFilter
      )
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

private struct TasksReviewOptionsMenu: View {
  @Binding var isTableMode: Bool
  @Binding var priorityFilter: LorvexTask.Priority?

  private var label: String {
    String(localized: "tasks.view.menu", defaultValue: "View Options", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var systemImage: String {
    priorityFilter == nil ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill"
  }

  var body: some View {
    Menu {
      Picker(
        String(localized: "tasks.view.mode", defaultValue: "View", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: $isTableMode
      ) {
        Label(
          String(localized: "tasks.view.list", defaultValue: "Queue", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "checklist"
        )
        .tag(false)

        Label(
          String(localized: "tasks.view.table", defaultValue: "Audit", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "tablecells"
        )
        .tag(true)
      }
      .accessibilityIdentifier("tasks.header.viewMode")

      Divider()

      Picker(
        String(localized: "tasks.filter.priority", defaultValue: "Priority", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: $priorityFilter
      ) {
        Text(String(localized: "tasks.filter.all", defaultValue: "All", table: "Localizable", bundle: LorvexL10n.bundle))
          .tag(nil as LorvexTask.Priority?)
        ForEach(LorvexTask.Priority.allCases, id: \.self) { priority in
          Text(TaskDisplayText.compactPriority(priority))
            .tag(Optional(priority))
        }
      }
      .accessibilityIdentifier("tasks.header.priorityFilter")
      .disabled(isTableMode)
    } label: {
      Label(label, systemImage: systemImage)
    }
    .workspaceHeaderLabeledActionStyle()
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier("tasks.header.viewOptions")
  }
}

private struct TasksSelectionActionMenu: View {
  @Bindable var store: AppStore

  var body: some View {
    Menu {
      TaskBatchActionMenuContent(
        store: store,
        selectionSurface: .taskWorkspace,
        canActOnSelection: store.taskWorkspaceSelectedTasks.contains {
          $0.status.isActive
        },
        canReopenSelection: store.taskWorkspaceSelectedTasks.contains {
          $0.status.isResolved
        },
        canMoveSelectionToSomeday: store.taskWorkspaceSelectedTasks.contains { $0.status == .open },
        complete: { Task { await store.completeTaskWorkspaceSelection() } },
        deferToTomorrow: { Task { await store.deferTaskWorkspaceSelection() } },
        cancel: { Task { await store.cancelTaskWorkspaceSelection() } },
        reopen: { Task { await store.reopenTaskWorkspaceSelection() } },
        moveToSomeday: { Task { await store.markTaskWorkspaceSelectionSomeday() } },
        move: { listID in Task { await store.moveTaskWorkspaceSelection(toListID: listID) } }
      )
    } label: {
      Label(
        selectionActionsLabel,
        systemImage: "checklist.checked"
      )
    }
    .workspaceHeaderLabeledActionStyle()
    .help(selectionActionsLabel)
    .accessibilityLabel(selectionActionsAccessibilityLabel)
    .accessibilityIdentifier("tasks.header.selectionActions")
  }

  private var selectionActionsLabel: String {
    String(
      localized: "tasks.header.selection_actions",
      defaultValue: "Selection Actions",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
  }

  private var selectionActionsAccessibilityLabel: String {
    String(
      format: String(
        localized: "tasks.selection.count",
        defaultValue: "%lld selected",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      store.taskWorkspaceSelectionCount
    )
  }
}
