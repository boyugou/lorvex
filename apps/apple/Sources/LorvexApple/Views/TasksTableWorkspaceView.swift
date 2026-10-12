import LorvexCore
import SwiftUI

/// Column widths in points. The table gets about 716 pt at the smallest
/// three-pane window (inspector open), and each column takes about 17 pt of cell
/// padding beyond its width. A `Table` squeezes its columns toward their
/// minimums when it is narrower than their ideals but never below them, and then
/// scrolls sideways, which cuts the last column at the table's edge. The five
/// minimums plus that padding therefore stay under 716 pt, with the title, the
/// column that truncates, giving the most; a wider window spreads the spare
/// width across the columns up to their maximums.
private enum TasksTableMetrics {
  static let minSurfaceHeight: CGFloat = 360
  static let statusColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (108, 108, 140)
  static let priorityColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (80, 80, 104)
  static let titleColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (200, 280, 820)
  static let dueColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (108, 108, 144)
  static let listColumn: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (120, 120, 220)
}

/// Flat, sortable `Table` view for the macOS Tasks workspace.
///
/// Shows all tasks across every status (open, deferred, someday, completed,
/// cancelled) in a single table with sortable Priority, Status, Title, Due,
/// and List columns. Cells use the same compact semantic tokens as task rows,
/// so audit mode is denser without turning into a wall of status text.
/// Multi-selection (Set<ID>) is shared with the List workspace so batch actions
/// work identically in both view modes. Scoped to one list, the table drops its
/// List column, since every row would repeat the list the header names. A row
/// drags like a list-mode row: onto a sidebar list to move it, with the whole
/// selection riding along when the row is one of several selected.
struct TasksTableWorkspaceView: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager
  let tasks: [LorvexTask]
  let sortOrder: Binding<[KeyPathComparator<LorvexTask>]>
  let selection: Binding<Set<LorvexTask.ID>>

  var body: some View {
    // Compute the list-name lookup once per render and thread it into the table,
    // rather than rebuilding the dictionary on every `body`/cell access.
    let listNames = Dictionary(
      uniqueKeysWithValues: (store.lists?.lists ?? []).map { ($0.id, $0.displayName) })
    return WorkspaceAuditLane {
      table(sortedTasks: tasks, listNames: listNames)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: TasksTableMetrics.minSurfaceHeight)
        .lorvexInsetPanel(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
        .accessibilityIdentifier("tasks.table.auditSurface")
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.m)
  }

  private func table(sortedTasks: [LorvexTask], listNames: [String: String]) -> some View {
    let searchQuery = store.trimmedSearchText
    let isListScoped = store.taskWorkspaceListScopeID != nil
    return Table(of: LorvexTask.self, selection: selection, sortOrder: sortOrder) {
      TableColumn(
        String(localized: "tasks.column.status", defaultValue: "Status", table: "Localizable", bundle: LorvexL10n.bundle),
        value: \.status
      ) { task in
        TaskTableStatusCell(status: task.status, isBlocked: store.isBlocked(task))
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
        TaskTableTitleCell(
          task: task,
          searchMatch: searchQuery.isEmpty
            ? nil : task.searchMatch(for: searchQuery, visibleTagCount: LorvexTaskRow.visibleTagCount))
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

      if !isListScoped {
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
    } rows: {
      ForEach(sortedTasks) { task in
        TableRow(task)
          .draggable(store.taskDragPayload(for: task, on: .taskWorkspace))
      }
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
          complete: { Task { await store.completeTaskWorkspaceSelection(undoManager: undoManager) } },
          deferToTomorrow: { Task { await store.deferTaskWorkspaceSelection() } },
          cancel: { Task { await store.cancelTaskWorkspaceSelection() } },
          reopen: { Task { await store.reopenTaskWorkspaceSelection() } },
          moveToSomeday: { Task { await store.markTaskWorkspaceSelectionSomeday() } },
          move: { listID in
            Task { await store.moveTaskWorkspaceSelection(toListID: listID, undoManager: undoManager) }
          }
        )
      }
    }
    .cancelSelectedTaskOnDelete(store, on: .taskWorkspace)
    .copySelectedTasksAsText(store, on: .taskWorkspace)
  }
}

/// A task's state in words. An open task whose dependencies are unfinished
/// reads "Blocked" with the lock its list-row badge uses, in place of "Open";
/// every other state keeps its own word and symbol.
private struct TaskTableStatusCell: View {
  let status: LorvexTask.Status
  var isBlocked = false

  private var showsBlocked: Bool { isBlocked && status == .open }

  var body: some View {
    let name = showsBlocked ? TaskDisplayText.blocked : status.localizedName
    Label(name, systemImage: showsBlocked ? "lock.fill" : status.statusSymbolName)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(showsBlocked ? LorvexDesign.Palette.blocked : status.statusTint)
      .lineLimit(1)
      .accessibilityLabel(name)
  }
}

private struct TaskTablePriorityCell: View {
  let priority: LorvexTask.Priority

  var body: some View {
    Text(priority.localizedName)
      .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
      .foregroundStyle(priority.priorityTint)
      .padding(.horizontal, LorvexDesign.Spacing.sm)
      .padding(.vertical, LorvexDesign.Spacing.xxs)
      .background(priority.priorityTint.opacity(0.10), in: Capsule())
      .accessibilityLabel(priority.localizedPhrase)
  }
}

private struct TaskTableTitleCell: View {
  let task: LorvexTask
  /// Why the task is in the search results when its title does not show the
  /// searched word, quoted under the title as in list mode
  /// (``LorvexTask/searchMatch(for:visibleTagCount:)``).
  var searchMatch: LorvexTaskSearchMatch? = nil

  private var isInactive: Bool {
    task.status.isResolved
  }

  /// Finished, cancelled and parked (Someday) tasks read muted, as a list row's
  /// title does; only the resolved ones are struck through.
  private var isDormant: Bool { isInactive || task.status == .someday }

  private var secondaryText: String? {
    var parts: [String] = []
    if let minutes = task.estimatedMinutes { parts.append(LorvexDurationFormat.minutes(minutes)) }
    parts.append(contentsOf: task.tags.prefix(3))
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// The estimate and tags line as VoiceOver reads it: the same spelled-out
  /// duration and `#tag` words a list row's label uses, in place of the
  /// abbreviation and the middle dots the line draws.
  private var secondarySpokenText: String? {
    var parts: [String] = []
    if let minutes = task.estimatedMinutes {
      parts.append(LorvexDurationFormat.minutes(minutes, style: .spoken))
    }
    parts.append(contentsOf: task.tags.prefix(3).map { "#\($0)" })
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(task.title)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .strikethrough(isInactive, color: .secondary)
        .lineLimit(1)
      if let searchMatch { LorvexSearchExcerptLine(match: searchMatch) }
      if let secondaryText {
        Text(secondaryText)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityLabel(secondarySpokenText ?? secondaryText)
      }
    }
  }
}

private struct TaskTableDueCell: View {
  let task: LorvexTask
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    // Equivalent display to task.dueRelativeLabel(), but backed by the cached
    // core formatter and computed once for this cell body.
    let label = task.cachedDueRelativeLabel(timeZone: productTimeZone)
    let isOverdue = task.isOverdue(timeZone: productTimeZone)
    let isDueSoon = task.isDueSoon(timeZone: productTimeZone)
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
      .foregroundStyle(
        isOverdue
          ? AnyShapeStyle(LorvexDesign.Palette.overdue)
          : isDueSoon ? AnyShapeStyle(LorvexDesign.Palette.dueSoon) : AnyShapeStyle(.secondary))
      .padding(.horizontal, isOverdue ? LorvexDesign.Spacing.sm : 0)
      .padding(.vertical, isOverdue ? LorvexDesign.Spacing.xxs : 0)
      .background {
        if isOverdue {
          Capsule()
            .fill(LorvexDesign.Palette.overdue.opacity(0.10))
        }
      }
      .accessibilityLabel(taskDueAccessibilityPhrase(task, timeZone: productTimeZone) ?? label)
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
