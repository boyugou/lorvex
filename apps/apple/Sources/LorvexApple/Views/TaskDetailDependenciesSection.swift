import LorvexCore
import SwiftUI

extension TaskDetailView {
  /// The Dependencies inspector section: the tasks this task is blocked by,
  /// shown by title as removable rows, plus an "Add dependency" control that
  /// opens a searchable, cycle-safe candidate picker. Edits flow through
  /// `store.taskDetailDependencies` (the ordered-ID projection over the same
  /// draft the save path reads), so the section drives the existing `dependsOn`
  /// save contract without a new write path.
  func dependenciesContent(task: LorvexTask) -> some View {
    TaskDetailDependenciesPanel(store: store, ownTaskID: task.id)
  }
}

/// Current dependencies as title-resolved rows over the task search that adds
/// one, so a task with no dependencies opens straight on the search and one
/// pick adds it (and closes the popover). Binds to `store.taskDetailDependencies`; titles are resolved
/// through `store.dependencyTasks(for:)`. A row's circle completes (or
/// reopens) that task in place; clicking the rest of the row opens it in the
/// detail's place and closes the popover the panel sits in. A target the store
/// can no longer resolve (deleted / archived) renders as a muted,
/// still-removable "unavailable" row.
private struct TaskDetailDependenciesPanel: View {
  @Bindable var store: AppStore
  let ownTaskID: LorvexTask.ID

  @Environment(\.dismiss) private var dismiss
  @Environment(\.undoManager) private var undoManager
  @State private var resolved: [LorvexTask] = []

  private var dependencyIDs: [LorvexTask.ID] { store.taskDetailDependencies }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        if !dependencyIDs.isEmpty {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            ForEach(dependencyIDs, id: \.self) { id in
              TaskDetailDependencyRow(
                task: resolved.first { $0.id == id },
                open: open,
                toggleCompletion: toggleCompletion,
                remove: { remove(id) }
              )
              .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
          .accessibilityElement(children: .contain)
          .accessibilityLabel(String(
            localized: "task_detail.dependencies.a11y", defaultValue: "Task dependencies",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("task.detail.dependencies")
          Divider()
        }

        TaskDetailDependencyPicker(
          excludedIDs: Set(dependencyIDs).union([ownTaskID]),
          listHeight: dependencyIDs.isEmpty ? 300 : 200,
          cycleExclusions: { await store.dependencyCycleExclusions(for: ownTaskID) },
          searchCandidates: { query, excluded in
            await store.dependencyCandidates(matching: query, excluding: excluded)
          },
          onSelect: { add($0) }
        )
    }
    .accessibilityIdentifier("task.detail.dependencies.panel")
    .task(id: dependencyIDs) {
      resolved = await store.dependencyTasks(for: dependencyIDs)
    }
  }

  private func open(_ task: LorvexTask) {
    dismiss()
    store.openDependency(task)
  }

  /// Completes or reopens a dependency, then re-reads the rows so its circle
  /// and facts show the new status.
  private func toggleCompletion(_ task: LorvexTask) {
    Task {
      await store.toggleTaskCompletion(task, undoManager: undoManager)
      resolved = await store.dependencyTasks(for: dependencyIDs)
    }
  }

  private func add(_ task: LorvexTask) {
    guard !dependencyIDs.contains(task.id) else { return }
    lorvexAnimated(.snappy(duration: 0.2)) {
      store.taskDetailDependencies.append(task.id)
    }
    if !resolved.contains(where: { $0.id == task.id }) {
      resolved.append(task)
    }
  }

  private func remove(_ id: LorvexTask.ID) {
    lorvexAnimated(.snappy(duration: 0.2)) {
      store.taskDetailDependencies.removeAll { $0 == id }
    }
  }
}

/// One task the detail's task waits on, as a nested task row: the task's
/// circle, which completes or reopens it like every task row's, its title, and
/// whether it has been started and when it is due (``TaskDependencyFacts``).
/// Clicking the title opens that task; the trailing button removes the
/// dependency, leaving the task itself alone. A target the store can no longer
/// resolve (deleted or archived) is muted, reads "Unavailable", opens nothing,
/// and stays removable.
private struct TaskDetailDependencyRow: View {
  let task: LorvexTask?
  let open: (LorvexTask) -> Void
  let toggleCompletion: (LorvexTask) -> Void
  let remove: () -> Void

  @State private var isHovering = false

  private var title: String {
    task?.title
      ?? String(
        localized: "task_detail.dependencies.unavailable", defaultValue: "Unavailable",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
  }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if let task {
        // The circle sits on the title's first line, as on a task row, rather
        // than floating beside the middle of a title that wraps.
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          completionCircle(task)
          Button {
            open(task)
          } label: {
            summary(task)
          }
          .buttonStyle(.plain)
          .help(String(
            format: String(
              localized: "task_detail.dependencies.open.help", defaultValue: "Open “%@”",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            task.title))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(task.title)
          .accessibilityValue(TaskDependencyFacts.accessibilityValue(for: task))
          .accessibilityHint(String(
            localized: "task_detail.dependencies.open.a11y_hint", defaultValue: "Opens the task.",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("task.detail.dependencies.open")
        }
      } else {
        unavailableSummary
      }
      removeButton
    }
    .padding(.leading, LorvexDesign.Spacing.s)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
        .fill(.quaternary.opacity(isHovering && task != nil ? 1 : 0)))
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .contain)
  }

  /// The task row's checkbox: it completes an open dependency and reopens a
  /// done one. A cancelled or Someday task has no check-off, as on every task
  /// row.
  private func completionCircle(_ task: LorvexTask) -> some View {
    let label = TaskDisplayText.completionToggle(isDone: task.status == .completed)
    return Button {
      toggleCompletion(task)
    } label: {
      Image(systemName: task.statusCircleGlyph)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(task.statusCircleStyle)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 16)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(task.status == .cancelled || task.status == .someday)
    .help(label)
    .accessibilityLabel(lorvexPairLabel(label, task.title))
    .accessibilityIdentifier("task.detail.dependencies.complete")
  }

  private func summary(_ task: LorvexTask) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(task.title)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(task.status.isResolved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(2)
      if let facts = TaskDependencyFacts(task: task) {
        facts
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var unavailableSummary: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "circle.dashed")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.tertiary)
        .frame(width: 16)
      Text(title)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var removeButton: some View {
    LorvexIconButton(
      systemImage: "xmark",
      label: String(
        format: String(
          localized: "task_detail.dependencies.remove.a11y", defaultValue: "Remove dependency %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        title),
      accessibilityIdentifier: "task.detail.dependencies.remove",
      action: remove)
  }
}

/// Searchable candidate picker for adding a dependency, presented as a macOS
/// popover. An empty query lists actionable tasks; typing filters by title.
/// `excludedIDs` (self + already-selected) and the `cycleExclusions` set (tasks
/// that would close a dependency cycle, loaded once when the popover appears) are
/// filtered out by the candidate provider. Selecting a row appends it and
/// dismisses; ↑/↓ move the highlight, Return activates it, Escape closes.
private struct TaskDetailDependencyPicker: View {
  let excludedIDs: Set<LorvexTask.ID>
  /// The height of the search results under the field.
  var listHeight: CGFloat = 300
  let cycleExclusions: () async -> Set<LorvexTask.ID>
  let searchCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let onSelect: (LorvexTask) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var candidates: [LorvexTask] = []
  @State private var isSearching = false
  @State private var cycleSet: Set<LorvexTask.ID> = []
  @State private var didLoadCycleSet = false
  @State private var highlightedIndex = 0
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      resultsList
    }
    .frame(width: 320, height: listHeight + 40)
    // A single-line TextField does not consume vertical arrows, so the picker
    // can move the highlight while the field keeps text focus.
    .onKeyPress(.upArrow) {
      moveHighlight(-1)
      return .handled
    }
    .onKeyPress(.downArrow) {
      moveHighlight(1)
      return .handled
    }
    .onExitCommand { dismiss() }
    .accessibilityIdentifier("task.detail.dependencies.picker")
    .task { fieldFocused = true }
    .task(id: query) { await reload() }
  }

  private var searchField: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(
        String(
          localized: "task_detail.dependencies.search_placeholder", defaultValue: "Search tasks",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        text: $query
      )
      .textFieldStyle(.plain)
      .font(LorvexDesign.Typography.primaryText)
      .focused($fieldFocused)
      .onSubmit(activateHighlighted)
      .accessibilityIdentifier("task.detail.dependencies.search")
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
  }

  private var resultsList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
          if isSearching, candidates.isEmpty {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity)
              .padding(LorvexDesign.Spacing.l)
          } else if candidates.isEmpty {
            emptyResults
          } else {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, task in
              candidateRow(task, index: index)
                .id(task.id)
            }
          }
        }
        .padding(LorvexDesign.Spacing.xs)
      }
      .onChange(of: highlightedIndex) { _, index in
        guard candidates.indices.contains(index) else { return }
        proxy.scrollTo(candidates[index].id, anchor: .center)
      }
    }
  }

  private var emptyResults: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text(LocalizedStringResource(
        "task_detail.dependencies.no_matches", defaultValue: "No Matching Tasks",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(LorvexDesign.Spacing.l)
    .accessibilityIdentifier("task.detail.dependencies.noMatches")
  }

  private func candidateRow(_ task: LorvexTask, index: Int) -> some View {
    Button {
      onSelect(task)
      dismiss()
    } label: {
      VStack(alignment: .leading, spacing: 1) {
        Text(task.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let facts = TaskDependencyFacts(task: task) {
          facts
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(
        index == highlightedIndex
          ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering { highlightedIndex = index }
    }
    .accessibilityValue(TaskDependencyFacts.accessibilityValue(for: task))
    .accessibilityIdentifier("task.detail.dependencies.candidate")
  }

  private func reload() async {
    if !didLoadCycleSet {
      cycleSet = await cycleExclusions()
      didLoadCycleSet = true
    }
    isSearching = true
    let all = excludedIDs.union(cycleSet)
    candidates = await searchCandidates(query, all)
    highlightedIndex = 0
    isSearching = false
  }

  private func moveHighlight(_ delta: Int) {
    guard !candidates.isEmpty else { return }
    highlightedIndex = (highlightedIndex + delta + candidates.count) % candidates.count
  }

  private func activateHighlighted() {
    guard candidates.indices.contains(highlightedIndex) else { return }
    onSelect(candidates[highlightedIndex])
    dismiss()
  }
}

/// What a row for a task that another task waits on says under its title:
/// that the task has been started, and when it is due, in the overdue tint
/// once that day has passed, the way a task row shows both. A completed or
/// cancelled task shows neither, since its circle already says it is done.
/// `init(task:)` returns nil when neither fact applies, so such a row stays a
/// single title line. The task's priority and plain status are left to its
/// status circle, whose glyph and tint carry them.
private struct TaskDependencyFacts: View {
  let isStarted: Bool
  let due: String?
  let isOverdue: Bool

  init?(task: LorvexTask) {
    isStarted = task.status == .inProgress
    due = task.status.isResolved ? nil : task.cachedDueRelativeLabel()
    isOverdue = due != nil && task.isOverdue()
    guard isStarted || due != nil else { return nil }
  }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      if isStarted {
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Image(systemName: "play.fill")
          Text(Self.startedText)
        }
        .foregroundStyle(.tint)
      }
      if let due {
        if isStarted { Text(verbatim: "·").foregroundStyle(.tertiary) }
        HStack(spacing: LorvexDesign.Spacing.xs) {
          Image(systemName: isOverdue ? "clock.badge.exclamationmark" : "calendar")
          Text(due).monospacedDigit()
        }
        .foregroundStyle(isOverdue ? AnyShapeStyle(LorvexDesign.Palette.overdue) : AnyShapeStyle(.secondary))
      }
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .lineLimit(1)
    .accessibilityHidden(true)
  }

  private static var startedText: String {
    String(localized: "task.row.started", defaultValue: "Started", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// What VoiceOver reads after a dependency's title: its status, then when an
  /// unfinished one is due ("In Progress, due tomorrow"). The row's circle and
  /// facts line are not read aloud, so the status is always named here.
  static func accessibilityValue(for task: LorvexTask) -> String {
    let vocabulary = TaskAccessibilityVocabulary.lorvexLocalized
    var parts = [TaskDisplayText.status(task.status)]
    if !task.status.isResolved, let due = task.cachedDueRelativeLabel() {
      parts.append(String(format: task.isOverdue() ? vocabulary.overdueFormat : vocabulary.dueFormat, due))
    }
    return parts.joined(separator: ", ")
  }
}

#if DEBUG
  /// Renders the Dependencies panel over the seeded preview core so the section
  /// can be inspected in Xcode without launching the app. Selects the seeded task
  /// that carries dependency edges when one is present, otherwise the first task
  /// (which renders the empty state).
  private struct TaskDetailDependenciesPreviewHarness: View {
    @State private var store = AppStore(
      core: LorvexPreviewCoreFactory.makeUIPreviewSeededBlocking(todaySchedule: false))
    @State private var ownTaskID: LorvexTask.ID?

    var body: some View {
      Group {
        if let ownTaskID {
          TaskDetailView(store: store).dependenciesContent(task: previewTask(ownTaskID))
        } else {
          ProgressView()
        }
      }
      .padding(LorvexDesign.Spacing.l)
      .frame(width: 380)
      .task {
        await store.refresh()
        let selected = store.today.tasks.first { !$0.dependsOn.isEmpty }
          ?? store.today.tasks.first
        guard let selected else { return }
        store.selectedTaskID = selected.id
        store.syncSelectedTaskDraft()
        ownTaskID = selected.id
      }
    }

    private func previewTask(_ id: LorvexTask.ID) -> LorvexTask {
      store.today.tasks.first { $0.id == id } ?? store.today.tasks[0]
    }
  }

  #Preview("Task Dependencies") {
    TaskDetailDependenciesPreviewHarness()
  }
#endif
