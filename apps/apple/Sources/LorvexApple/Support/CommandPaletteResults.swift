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
  /// `subtitle` is the dimmed line under the title
  /// (``CommandPaletteResults/taskSubtitle(_:listNames:now:timeZone:)``);
  /// `nil` when the task has nothing worth surfacing. `isDone` marks a
  /// completed or cancelled task, whose row leads with a check instead of an
  /// empty circle.
  case openTask(id: LorvexTask.ID, title: String, subtitle: String?, isDone: Bool = false)
  /// Open a list in the Tasks workspace, as its sidebar row does. `icon` and
  /// `colorHex` are the list's own, so the row wears the sidebar's icon.
  case openList(id: LorvexList.ID, name: String, icon: String?, colorHex: String?)
  /// Capture a new task from the current query text.
  case createTask(title: String)
  /// Run a global app command (refresh, new task window, …).
  case action(AppCommand)

  var id: String {
    switch self {
    case .navigate(let selection): "navigate.\(selection.rawValue)"
    case .openTask(let id, _, _, _): "task.\(id)"
    case .openList(let id, _, _, _): "list.\(id)"
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
    case .openTask(_, let title, _, _):
      return title
    case .openList(_, let name, _, _):
      return name
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
    case .openTask(_, _, _, let isDone): isDone ? "checkmark.circle" : "circle"
    case .openList: "folder"
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
    case "Lists":
      String(localized: "command_palette.group.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle)
    case "Tasks":
      String(localized: "command_palette.group.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
    case "Actions":
      String(localized: "command_palette.group.actions", defaultValue: "Actions", table: "Localizable", bundle: LorvexL10n.bundle)
    default:
      title
    }
  }
}

/// Pure result-building for the command palette. Given the typed query, the
/// current task pool, and the lists, produces the grouped, ordered result list
/// the palette renders. No view, store, or actor state — every input is passed
/// in so the transformation is unit-testable in isolation.
enum CommandPaletteResults {
  /// Maximum number of task matches surfaced, keeping the palette scannable.
  static let taskResultLimit = 8

  /// Builds grouped results for `rawQuery` against `tasks` and `lists`.
  /// `lists` may include archived lists: they name the tasks they hold, but
  /// only active lists are offered as places to open. `now` dates the task
  /// rows' relative due labels.
  ///
  /// - Empty query: shows every navigation destination plus the global actions,
  ///   so the palette doubles as a launcher with nothing typed.
  /// - Non-empty query: navigation destinations and lists whose name contains
  ///   the query, up to ``taskResultLimit`` tasks matching via
  ///   `LorvexTask.matchesSearch`, matching global actions, and a "New Task"
  ///   group that captures the query as a task.
  ///
  /// The first row is what Return does, so it follows the query's intent. A
  /// query that begins a destination's or a list's name, or one of its words,
  /// is a jump, and those groups lead; any other query leads with capture.
  /// Task matches never lead, so capturing a title an existing task shares
  /// still creates the new task. A task's due day is counted from the day
  /// `now` falls on in `timeZone`, the product time zone.
  static func groups(
    query rawQuery: String,
    tasks: [LorvexTask],
    lists: [LorvexList] = [],
    now: Date = Date(),
    timeZone: TimeZone = .current,
    destinations: [SidebarSelection] = SidebarSelection.mainNavigationItems,
    actions: [AppCommand] = AppCommand.allCases
  ) -> [CommandPaletteGroup] {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let matchedDestinations =
      query.isEmpty
      ? destinations
      : destinations.filter { names(of: $0).contains { $0.containsSearchTerm(query) } }
    let matchedLists =
      query.isEmpty
      ? []
      : lists.filter { !$0.isArchived && $0.displayName.containsSearchTerm(query) }

    var jumps: [CommandPaletteGroup] = []
    if !matchedDestinations.isEmpty {
      jumps.append(
        CommandPaletteGroup(title: "Navigation", results: matchedDestinations.map { .navigate($0) }))
    }
    if !matchedLists.isEmpty {
      jumps.append(
        CommandPaletteGroup(
          title: "Lists",
          results: matchedLists.map {
            .openList(id: $0.id, name: $0.displayName, icon: $0.icon, colorHex: $0.color)
          }))
    }

    var groups: [CommandPaletteGroup] = []
    if query.isEmpty {
      groups = jumps
    } else {
      let capture = CommandPaletteGroup(title: "New Task", results: [.createTask(title: query)])
      let isJump =
        matchedDestinations.contains { names(of: $0).contains { beginsNameOrWord($0, query: query) } }
        || matchedLists.contains { beginsNameOrWord($0.displayName, query: query) }
      groups = isJump ? jumps + [capture] : [capture] + jumps

      let listNames = Dictionary(
        lists.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
      let taskResults =
        tasks
        .filter { $0.matchesSearch(query) }
        .prefix(taskResultLimit)
        .map {
          CommandPaletteResult.openTask(
            id: $0.id, title: $0.title, subtitle: taskSubtitle($0, listNames: listNames, now: now, timeZone: timeZone),
            isDone: $0.status.isResolved)
        }
      if !taskResults.isEmpty {
        groups.append(CommandPaletteGroup(title: "Tasks", results: Array(taskResults)))
      }
    }

    let actionResults =
      query.isEmpty
      ? actions.map { CommandPaletteResult.action($0) }
      : actions
        .filter { $0.title.containsSearchTerm(query) }
        .map { CommandPaletteResult.action($0) }
    if !actionResults.isEmpty {
      groups.append(CommandPaletteGroup(title: "Actions", results: actionResults))
    }

    return groups
  }

  /// The names a destination answers to: its stable English title and the
  /// title the sidebar shows in the current language ("Reviews" and "Review",
  /// or "Calendar" and "日历").
  private static func names(of destination: SidebarSelection) -> [String] {
    [destination.macOSDisplayTitle, String(localized: destination.macOSLocalizedTitle)]
  }

  /// Whether `query` begins `name` or one of its words, ignoring case and
  /// diacritics: "hab" begins "Habits", and "nat" begins "Apple Native".
  static func beginsNameOrWord(_ name: String, query: String) -> Bool {
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
    if name.range(of: query, options: options) != nil { return true }
    return name.split(whereSeparator: \.isWhitespace).contains {
      $0.range(of: query, options: options) != nil
    }
  }

  /// The flat, ordered list of results across every group — the sequence the
  /// up/down arrow selection moves through.
  static func flatResults(_ groups: [CommandPaletteGroup]) -> [CommandPaletteResult] {
    groups.flatMap(\.results)
  }

  /// The dimmed line under a task row: what tells two similar tasks apart. It
  /// names the list that holds the task (from `listNames`), then, for a task
  /// still to do, when it is due relative to `now` ("Due today") and its status
  /// unless it is simply open; a finished or cancelled task says so instead of
  /// when it was due. `nil` when none of these applies.
  static func taskSubtitle(
    _ task: LorvexTask, listNames: [LorvexList.ID: String] = [:], now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String? {
    var parts: [String] = []
    if let listID = task.listID, let name = listNames[listID] {
      parts.append(name)
    }
    switch task.status {
    case .completed, .cancelled:
      parts.append(task.status.localizedName)
    case .open, .inProgress, .someday:
      if let due = task.cachedDueRelativeLabel(now: now, timeZone: timeZone) {
        parts.append(
          String(
            format: String(
              localized: "command_palette.task.due", defaultValue: "Due %@", table: "Localizable",
              bundle: LorvexL10n.bundle),
            due))
      }
      if task.status != .open {
        parts.append(task.status.localizedName)
      }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
