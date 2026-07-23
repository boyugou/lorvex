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

/// Current dependencies as removable, title-resolved rows over an "Add
/// dependency" control. Binds to `store.taskDetailDependencies`; titles are
/// resolved through `store.dependencyTasks(for:)`, and a target the store can no
/// longer resolve (deleted / archived) renders as a muted, still-removable
/// "unavailable" row.
private struct TaskDetailDependenciesPanel: View {
  @Bindable var store: AppStore
  let ownTaskID: LorvexTask.ID

  @State private var resolved: [LorvexTask] = []
  @State private var isPickerPresented = false

  private var dependencyIDs: [LorvexTask.ID] { store.taskDetailDependencies }

  var body: some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.dependencies.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        if dependencyIDs.isEmpty {
          emptyState
        } else {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            ForEach(dependencyIDs, id: \.self) { id in
              dependencyRow(id)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
          .accessibilityElement(children: .contain)
          .accessibilityLabel(String(
            localized: "task_detail.dependencies.a11y", defaultValue: "Task dependencies",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
          .accessibilityIdentifier("task.detail.dependencies")
        }

        addButton
      }
    }
    .task(id: dependencyIDs) {
      resolved = await store.dependencyTasks(for: dependencyIDs)
    }
  }

  private var emptyState: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(.tertiary)
      VStack(alignment: .leading, spacing: 2) {
        Text(LocalizedStringResource("task_detail.dependencies.empty", defaultValue: "No dependencies", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
        Text(LocalizedStringResource(
          "task_detail.dependencies.empty_hint",
          defaultValue: "Add tasks that must be finished first.",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(LorvexDesign.Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("task.detail.dependencies.empty")
  }

  private func dependencyRow(_ id: LorvexTask.ID) -> some View {
    let task = resolved.first { $0.id == id }
    return HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "arrow.triangle.branch")
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(task == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(rowTitle(task))
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(task == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimit(2)
        if let task {
          Text(TaskDisplayText.compactPriorityAndStatus(
            priority: task.priority, status: task.status))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
      Button {
        remove(id)
      } label: {
        Image(systemName: "minus.circle.fill")
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(
        format: String(
          localized: "task_detail.dependencies.remove.a11y", defaultValue: "Remove dependency %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        rowTitle(task)))
      .accessibilityIdentifier("task.detail.dependencies.remove")
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .background(.quaternary.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.12), lineWidth: 0.5)
    }
    .accessibilityElement(children: .combine)
  }

  private var addButton: some View {
    Button {
      isPickerPresented = true
    } label: {
      Label(
        String(
          localized: "task_detail.dependencies.add", defaultValue: "Add Dependency",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "plus.circle"
      )
      .font(LorvexDesign.Typography.secondaryText.weight(.medium))
      .foregroundStyle(.tint)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("task.detail.dependencies.add")
    .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
      TaskDetailDependencyPicker(
        excludedIDs: Set(dependencyIDs).union([ownTaskID]),
        cycleExclusions: { await store.dependencyCycleExclusions(for: ownTaskID) },
        searchCandidates: { query, excluded in
          await store.dependencyCandidates(matching: query, excluding: excluded)
        },
        onSelect: { add($0) }
      )
    }
  }

  private func rowTitle(_ task: LorvexTask?) -> String {
    task?.title
      ?? String(
        localized: "task_detail.dependencies.unavailable", defaultValue: "Unavailable",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
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

/// Searchable candidate picker for adding a dependency, presented as a macOS
/// popover. An empty query lists actionable tasks; typing filters by title.
/// `excludedIDs` (self + already-selected) and the `cycleExclusions` set (tasks
/// that would close a dependency cycle, loaded once when the popover appears) are
/// filtered out by the candidate provider. Selecting a row appends it and
/// dismisses; ↑/↓ move the highlight, Return activates it, Escape closes.
private struct TaskDetailDependencyPicker: View {
  let excludedIDs: Set<LorvexTask.ID>
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
    .frame(width: 320, height: 340)
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
        LazyVStack(alignment: .leading, spacing: 2) {
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
        Text(TaskDisplayText.compactPriorityAndStatus(
          priority: task.priority, status: task.status))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
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
