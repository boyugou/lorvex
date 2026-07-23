import Foundation
import LorvexCore

/// A single actionable row in the command palette. The view switches on the
/// case to perform the action against `AppStore`; the action is never captured
/// here so result building stays a pure, testable transformation.
enum CommandPaletteResult: Identifiable, Equatable {
  /// Switch the sidebar to a workspace destination.
  case navigate(SidebarSelection)
  /// Select an existing task and jump to it in the Tasks workspace.
  ///
  /// `subtitle` is the dimmed secondary line (`priority · status · due`) the
  /// palette renders under the title; `nil` when the task has no metadata worth
  /// surfacing.
  case openTask(id: LorvexTask.ID, title: String, subtitle: String?)
  /// Capture a new task from the current query text.
  case createTask(title: String)
  /// Run a global app command (refresh, new task window, …).
  case action(AppCommand)

  var id: String {
    switch self {
    case .navigate(let selection): "navigate.\(selection.rawValue)"
    case .openTask(let id, _, _): "task.\(id)"
    case .createTask: "create"
    case .action(let command): "action.\(command.id)"
    }
  }

  /// Localized row title shown in the palette UI, resolved at the view boundary.
  var localizedTitle: String {
    switch self {
    case .navigate(let selection):
      return String(
        format: String(
          localized: "command_palette.result.go_to",
          defaultValue: "Go to %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        String(localized: selection.macOSLocalizedTitle))
    case .openTask(_, let title, _):
      return title
    case .createTask(let title):
      return String(
        format: String(
          localized: "command_palette.result.create_task",
          defaultValue: "Create task “%@”",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        title)
    case .action(let command):
      return command.title
    }
  }

  /// SF Symbol shown beside the row.
  var systemImage: String {
    switch self {
    case .navigate(let selection): selection.systemImage
    case .openTask: "checklist"
    case .createTask: "plus.circle"
    case .action(let command): command.systemImage
    }
  }
}

/// A titled group of command-palette results (Navigation, Tasks, …).
struct CommandPaletteGroup: Identifiable, Equatable {
  let title: String
  let results: [CommandPaletteResult]
  var id: String { title }

  var localizedTitle: String {
    switch title {
    case "New Task":
      String(
        localized: "app.commands.new_task",
        defaultValue: "New Task",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case "Navigation":
      String(
        localized: "command_palette.group.navigation",
        defaultValue: "Navigation",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case "Tasks":
      String(localized: "command_palette.group.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case "Actions":
      String(localized: "command_palette.group.actions", defaultValue: "Actions", table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      title
    }
  }
}

/// Pure result-building for the command palette. Given the typed query and the
/// current task pool, produces the grouped, ordered result list the palette
/// renders. No view, store, or actor state — every input is passed in so the
/// transformation is unit-testable in isolation.
enum CommandPaletteResults {
  /// Maximum number of task matches surfaced, keeping the palette scannable.
  static let taskResultLimit = 8

  /// Builds grouped results for `rawQuery` against `tasks`.
  ///
  /// - Empty query: shows every navigation destination plus the global actions,
  ///   so the palette doubles as a launcher with nothing typed.
  /// - Non-empty query: a "New Task" group with a create action comes
  ///   first, then navigation destinations whose title matches, then up to
  ///   ``taskResultLimit`` tasks matching via `LorvexTask.matchesSearch`, then
  ///   matching global actions.
  static func groups(
    query rawQuery: String,
    tasks: [LorvexTask],
    destinations: [SidebarSelection] = SidebarSelection.mainNavigationItems,
    actions: [AppCommand] = AppCommand.allCases
  ) -> [CommandPaletteGroup] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    var groups: [CommandPaletteGroup] = []

    if !query.isEmpty {
      groups.append(
        CommandPaletteGroup(
          title: "New Task",
          results: [.createTask(title: query)]
        ))
    }

    let navResults =
      query.isEmpty
      ? destinations.map { CommandPaletteResult.navigate($0) }
      : destinations
        .filter {
          $0.macOSDisplayTitle.localizedCaseInsensitiveContains(query)
            || String(localized: $0.macOSLocalizedTitle).localizedCaseInsensitiveContains(query)
        }
        .map { CommandPaletteResult.navigate($0) }
    if !navResults.isEmpty {
      groups.append(CommandPaletteGroup(title: "Navigation", results: navResults))
    }

    if !query.isEmpty {
      let taskResults =
        tasks
        .filter { $0.matchesSearch(query) }
        .prefix(taskResultLimit)
        .map { CommandPaletteResult.openTask(id: $0.id, title: $0.title, subtitle: taskSubtitle($0)) }
      if !taskResults.isEmpty {
        groups.append(CommandPaletteGroup(title: "Tasks", results: Array(taskResults)))
      }
    }

    let actionResults =
      query.isEmpty
      ? actions.map { CommandPaletteResult.action($0) }
      : actions
        .filter { $0.title.localizedCaseInsensitiveContains(query) }
        .map { CommandPaletteResult.action($0) }
    if !actionResults.isEmpty {
      groups.append(CommandPaletteGroup(title: "Actions", results: actionResults))
    }

    return groups
  }

  /// The flat, ordered list of results across every group — the sequence the
  /// up/down arrow selection moves through.
  static func flatResults(_ groups: [CommandPaletteGroup]) -> [CommandPaletteResult] {
    groups.flatMap(\.results)
  }

  /// The dimmed `priority · status · due` secondary line for a task row.
  /// Priority and status are always present; the due date is appended only when
  /// the task has one.
  static func taskSubtitle(_ task: LorvexTask) -> String {
    var parts: [String] = [
      TaskDisplayText.compactPriorityAndStatus(priority: task.priority, status: task.status)
    ]
    if let due = task.dueDateDisplaySummary {
      parts.append(due)
    }
    return parts.joined(separator: " · ")
  }

  /// The case-insensitive ranges in `text` where `rawQuery` matches, in order and
  /// non-overlapping. Used to bold the matched substring in a result row. An
  /// empty or whitespace-only query, or no match, yields an empty array.
  ///
  /// Pure and deterministic so the row's highlight is unit-testable without a
  /// view: the caller maps these `Range<String.Index>` onto styled text runs.
  static func matchRanges(of rawQuery: String, in text: String) -> [Range<String.Index>] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    var ranges: [Range<String.Index>] = []
    var searchStart = text.startIndex
    while searchStart < text.endIndex,
      let range = text.range(
        of: query, options: .caseInsensitive, range: searchStart..<text.endIndex)
    {
      ranges.append(range)
      searchStart = range.upperBound
    }
    return ranges
  }
}
