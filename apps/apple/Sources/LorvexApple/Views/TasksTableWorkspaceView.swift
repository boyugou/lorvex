import LorvexCore
import SwiftUI

private enum TasksTableMetrics {
  static let minSurfaceHeight: CGFloat = 360
  static let statusColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (92, 112, 132)
  static let priorityColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (56, 64, 76)
  static let titleColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (320, 560, 820)
  static let dueColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (88, 108, 132)
  static let listColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (120, 160, 220)
}

/// Flat, sortable `Table` view for the macOS Tasks workspace.
///
/// Shows all tasks across every status (open, deferred, someday, completed,
/// cancelled) in a single table with sortable Priority, Status, Title, Due,
/// and List columns. Cells use the same compact semantic tokens as task rows,
/// so audit mode is denser without turning into a wall of status text.
/// Multi-selection (Set<ID>) is shared with the List workspace so batch actions
/// work identically in both view modes.
struct TasksTableWorkspaceView: View {
  @Bindable var store: AppStore
  let tasks: [LorvexTask]
  let sortOrder: Binding<[KeyPathComparator<LorvexTask>]>
  let selection: Binding<Set<LorvexTask.ID>>

  var body: some View {
    // Compute the list-name lookup once per render and thread it into the table,
    // rather than rebuilding the dictionary on every `body`/cell access.
    let listNames = Dictionary(
      uniqueKeysWithValues: (store.lists?.lists ?? []).map { ($0.id, $0.name) })
    return WorkspaceAuditLane {
      table(sortedTasks: tasks, listNames: listNames)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: TasksTableMetrics.minSurfaceHeight)
        .background(.quaternary.opacity(0.05), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        .overlay {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
            .stroke(.separator.opacity(0.18), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        .accessibilityIdentifier("tasks.table.auditSurface")
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.m)
  }

  private func table(sortedTasks: [LorvexTask], listNames: [String: String]) -> some View {
    Table(sortedTasks, selection: selection, sortOrder: sortOrder) {
      TableColumn(
        String(localized: "tasks.column.status", defaultValue: "Status", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.status
      ) { task in
        TaskTableStatusCell(status: task.status)
      }
      .width(
        min: TasksTableMetrics.statusColumn.min,
        ideal: TasksTableMetrics.statusColumn.ideal,
        max: TasksTableMetrics.statusColumn.max
      )

      TableColumn(
        String(localized: "tasks.column.priority", defaultValue: "Priority", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.priority
      ) { task in
        TaskTablePriorityCell(priority: task.priority)
      }
      .width(
        min: TasksTableMetrics.priorityColumn.min,
        ideal: TasksTableMetrics.priorityColumn.ideal,
        max: TasksTableMetrics.priorityColumn.max
      )

      TableColumn(
        String(localized: "tasks.column.title", defaultValue: "Title", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.title
      ) { task in
        TaskTableTitleCell(task: task)
      }
      .width(
        min: TasksTableMetrics.titleColumn.min,
        ideal: TasksTableMetrics.titleColumn.ideal,
        max: TasksTableMetrics.titleColumn.max
      )

      TableColumn(
        String(localized: "tasks.column.due", defaultValue: "Due", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.dueDate,
        comparator: OptionalDateComparator()
      ) { task in
        TaskTableDueCell(task: task)
      }
      .width(
        min: TasksTableMetrics.dueColumn.min,
        ideal: TasksTableMetrics.dueColumn.ideal,
        max: TasksTableMetrics.dueColumn.max
      )

      TableColumn(
        String(localized: "tasks.column.list", defaultValue: "List", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.listID,
        comparator: ListNameComparator(namesByID: listNames)
      ) { task in
        if let listID = task.listID, let name = listNames[listID] {
          Text(name)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .width(
        min: TasksTableMetrics.listColumn.min,
        ideal: TasksTableMetrics.listColumn.ideal,
        max: TasksTableMetrics.listColumn.max
      )
    }
    .contextMenu(forSelectionType: LorvexTask.ID.self) { ids in
      let selectedTasks = sortedTasks.filter { ids.contains($0.id) }
      if let task = selectedTasks.first, selectedTasks.count == 1 {
        WorkspaceTaskContextMenu(store: store, task: task)
      } else if selectedTasks.count > 1 {
        TaskBatchActionMenuContent(
          store: store,
          selectionSurface: .taskWorkspace,
          canActOnSelection: selectedTasks.contains {
            $0.status.isActive
          },
          canReopenSelection: selectedTasks.contains {
            $0.status.isResolved
          },
          canMoveSelectionToSomeday: selectedTasks.contains { $0.status == .open },
          complete: { Task { await store.completeTaskWorkspaceSelection() } },
          deferToTomorrow: { Task { await store.deferTaskWorkspaceSelection() } },
          cancel: { Task { await store.cancelTaskWorkspaceSelection() } },
          reopen: { Task { await store.reopenTaskWorkspaceSelection() } },
          moveToSomeday: { Task { await store.markTaskWorkspaceSelectionSomeday() } },
          move: { listID in Task { await store.moveTaskWorkspaceSelection(toListID: listID) } }
        )
      }
    }
    .cancelSelectedTaskOnDelete(store, on: .taskWorkspace)
  }
}

private struct TaskTableStatusCell: View {
  let status: LorvexTask.Status

  var body: some View {
    Label(TaskDisplayText.status(status), systemImage: status.statusSymbolName)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(status.statusTint)
      .lineLimit(1)
      .accessibilityLabel(TaskDisplayText.status(status))
  }
}

private struct TaskTablePriorityCell: View {
  let priority: LorvexTask.Priority

  var body: some View {
    Text(TaskDisplayText.compactPriority(priority))
      .font(LorvexDesign.Typography.tertiaryText.monospaced().weight(.semibold))
      .foregroundStyle(priority.priorityTint)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(priority.priorityTint.opacity(0.10), in: Capsule())
      .accessibilityLabel(TaskDisplayText.priority(priority))
  }
}

private struct TaskTableTitleCell: View {
  let task: LorvexTask

  private var isInactive: Bool {
    task.status.isResolved
  }

  private var secondaryText: String? {
    var parts: [String] = []
    if let minutes = task.estimatedMinutes { parts.append(lorvexMinutesLabel(minutes)) }
    parts.append(contentsOf: task.tags.prefix(3))
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(task.title)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(isInactive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .strikethrough(isInactive, color: .secondary)
        .lineLimit(1)
      if let secondaryText {
        Text(secondaryText)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
}

private struct TaskTableDueCell: View {
  let task: LorvexTask

  var body: some View {
    // Equivalent display to task.dueRelativeLabel(), but backed by the cached
    // core formatter and computed once for this cell body.
    let label = task.cachedDueRelativeLabel()
    let isOverdue = task.isOverdue()
    if let label {
      HStack(spacing: 4) {
        if isOverdue {
          Image(systemName: "clock.badge.exclamationmark")
            .accessibilityHidden(true)
        }
        Text(label)
          .monospacedDigit()
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(isOverdue ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
      .padding(.horizontal, isOverdue ? 6 : 0)
      .padding(.vertical, isOverdue ? 3 : 0)
      .background {
        if isOverdue {
          Capsule()
            .fill(.orange.opacity(0.10))
        }
      }
      .accessibilityLabel(label)
    }
  }
}

/// `KeyPathComparator`-compatible comparator for `Date?` columns: nil sorts
/// last so tasks without a due date appear at the bottom when sorting
/// ascending.
struct OptionalDateComparator: SortComparator {
  var order: SortOrder = .forward

  func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (.none, .none): return .orderedSame
    case (.none, .some): return order == .forward ? .orderedDescending : .orderedAscending
    case (.some, .none): return order == .forward ? .orderedAscending : .orderedDescending
    case let (.some(l), .some(r)):
      let cmp = l < r ? ComparisonResult.orderedAscending : l > r ? .orderedDescending : .orderedSame
      return order == .forward ? cmp : cmp.reversed
    }
  }
}

/// Sorts the List column by the resolved list *name* shown in each cell, not
/// the opaque `listID`. User-created lists carry a generated entity id, so an
/// id sort bears no relation to the displayed order. Tasks with no list (or an
/// unresolved id) sort last.
struct ListNameComparator: SortComparator {
  var order: SortOrder = .forward
  var namesByID: [String: String] = [:]

  func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    let lname = lhs.flatMap { namesByID[$0] }
    let rname = rhs.flatMap { namesByID[$0] }
    switch (lname, rname) {
    case (.none, .none): return .orderedSame
    case (.none, .some): return order == .forward ? .orderedDescending : .orderedAscending
    case (.some, .none): return order == .forward ? .orderedAscending : .orderedDescending
    case let (.some(l), .some(r)):
      // Finder-style numeric-aware ordering, matching the repo's standard for
      // user-facing name sorting (list names, etc.).
      let cmp = l.localizedStandardCompare(r)
      return order == .forward ? cmp : cmp.reversed
    }
  }

  // `namesByID` is not Hashable; hash on `order` only (collisions are allowed
  // and `==` still distinguishes differing name maps).
  func hash(into hasher: inout Hasher) {
    hasher.combine(order)
  }
}

private extension ComparisonResult {
  var reversed: ComparisonResult {
    switch self {
    case .orderedAscending: .orderedDescending
    case .orderedDescending: .orderedAscending
    case .orderedSame: .orderedSame
    }
  }
}
