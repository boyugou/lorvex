import LorvexCore
import SwiftUI

/// The Tasks workspace header: the Tasks symbol and "All Tasks", or, scoped to
/// a list, that list's own icon (in its color) and name, over one line saying
/// what the rows are — the active search and priority filter, else the list's
/// description, else the All Tasks caption.
///
/// It carries no counts. Every section below badges its own, so a digest here
/// could only repeat them, and for a paged section it would count just the rows
/// loaded so far. View options and the selection-actions menu ride in the
/// window toolbar (`TasksView`).
struct TasksWorkspaceHeader: View {
  let title: String
  let subtitle: String
  let icon: String
  /// The scoped list's color for its symbol icon; nil keeps the accent tint.
  let iconTint: Color?

  var body: some View {
    WorkspacePlanHeaderChrome {
      WorkspaceHeaderIdentity(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accessibilityIdentifier: "tasks.header.identity"
      )
      .tint(iconTint)
    }
  }
}

/// Queue/Audit view switch plus the priority filter, as a toolbar pull-down.
/// Both pickers are inline, so their choices sit in the menu itself under
/// their names rather than behind two one-item submenus. The label keeps its
/// title: the glyph alone does not say "view options".
struct TasksReviewOptionsMenu: View {
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
      .pickerStyle(.inline)
      .accessibilityIdentifier("tasks.header.viewMode")

      Divider()

      Picker(
        String(localized: "tasks.filter.priority", defaultValue: "Priority", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: $priorityFilter
      ) {
        Text(String(localized: "tasks.filter.all", defaultValue: "All", table: "Localizable", bundle: LorvexL10n.bundle))
          .tag(nil as LorvexTask.Priority?)
        ForEach(LorvexTask.Priority.allCases, id: \.self) { priority in
          Text(priority.localizedName)
            .tag(Optional(priority))
        }
      }
      .pickerStyle(.inline)
      .accessibilityIdentifier("tasks.header.priorityFilter")
      .disabled(isTableMode)
    } label: {
      Label(label, systemImage: systemImage)
        .labelStyle(.titleAndIcon)
    }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier("tasks.header.viewOptions")
  }
}

/// Batch actions over the multi-selected queue rows, shown in the toolbar only
/// while more than one row is selected.
struct TasksSelectionActionMenu: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager

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
        complete: { Task { await store.completeTaskWorkspaceSelection(undoManager: undoManager) } },
        deferToTomorrow: { Task { await store.deferTaskWorkspaceSelection() } },
        cancel: { Task { await store.cancelTaskWorkspaceSelection() } },
        reopen: { Task { await store.reopenTaskWorkspaceSelection() } },
        moveToSomeday: { Task { await store.markTaskWorkspaceSelectionSomeday() } },
        move: { listID in
          Task { await store.moveTaskWorkspaceSelection(toListID: listID, undoManager: undoManager) }
        }
      )
    } label: {
      Label(
        selectionActionsLabel,
        systemImage: "checklist.checked"
      )
      .labelStyle(.titleAndIcon)
    }
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
      localized: "tasks.selection.count",
      defaultValue: "\(store.taskWorkspaceSelectionCount) selected",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
