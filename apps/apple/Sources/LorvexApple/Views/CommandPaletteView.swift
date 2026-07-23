import LorvexCore
import SwiftUI

/// ⌘K command palette: a focused search field over a grouped result list for
/// fast keyboard-driven navigation, task search, quick capture, and global
/// actions. Result building lives in `CommandPaletteResults` (pure, tested);
/// this view owns presentation, focus, and keyboard handling.
struct CommandPaletteView: View {
  var store: AppStore
  @Environment(\.dismiss) private var dismiss

  @State private var query = ""
  @State private var taskResults: [LorvexTask] = []
  @State private var highlightedIndex = 0
  @FocusState private var fieldFocused: Bool
  // Keyboard navigation and query resets scroll the highlighted row into view;
  // pointer hover must not. Otherwise a trackpad scroll slides rows under the
  // stationary cursor, each `onHover` moves the highlight, the resulting
  // `scrollTo(anchor: .center)` recenters and fights the scroll, and the list
  // oscillates in place. Set true only for keyboard/query-driven changes.
  @State private var scrollsToHighlight = false
  // A failed task search surfaces here, inline. The shared `.lorvexErrorAlert`
  // lives on ContentView behind this `.sheet`, so on macOS it can't reliably
  // present over the palette — without an inline banner a backend error reads
  // as "no results."
  @State private var searchError: String?

  private var groups: [CommandPaletteGroup] {
    CommandPaletteResults.groups(query: query, tasks: taskResults)
  }

  private var flatResults: [CommandPaletteResult] {
    CommandPaletteResults.flatResults(groups)
  }

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      resultsList
    }
    .frame(width: 560, height: 420)
    .background(.regularMaterial)
    // A single-line TextField does not consume vertical arrows, so the palette
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
    .task { fieldFocused = true }
    .task(id: query) {
      scrollsToHighlight = true
      highlightedIndex = 0
      await loadTaskResults()
    }
  }

  private var searchField: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField(
        String(
          localized: "command_palette.search.placeholder",
          defaultValue: "Search tasks, navigate, or capture…",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        text: $query
      )
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.primaryText)
        .focused($fieldFocused)
        .onSubmit(activateHighlighted)
        .accessibilityIdentifier("commandPalette.field")
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.m)
  }

  private var resultsList: some View {
    let resultGroups = groups
    let flat = CommandPaletteResults.flatResults(resultGroups)
    // Resolve each result's flat index once per results set. Looking it up per
    // row (`firstIndex(where:)`) would be O(N) per row -> O(N^2) per render.
    let indexByID = Dictionary(
      flat.enumerated().map { (offset, result) in (result.id, offset) },
      uniquingKeysWith: { first, _ in first })
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          if let searchError {
            errorBanner(searchError)
          }
          if flat.isEmpty {
            if searchError == nil {
              Text(LocalizedStringResource("command_palette.empty.no_results", defaultValue: "No results", table: "Localizable", bundle: LorvexL10n.bundle))
                .font(LorvexDesign.Typography.secondaryText)
                .foregroundStyle(.secondary)
                .padding(LorvexDesign.Spacing.m)
            }
          } else {
            ForEach(resultGroups) { group in
              groupSection(group, indexByID: indexByID)
            }
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.s)
      }
      .onChange(of: highlightedIndex) { _, index in
        guard scrollsToHighlight else { return }
        scrollsToHighlight = false
        guard flat.indices.contains(index) else { return }
        proxy.scrollTo(flat[index].id, anchor: .center)
      }
    }
  }

  private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(LocalizedStringResource("common.error", defaultValue: "Error", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        Text(message)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .accessibilityIdentifier("commandPalette.searchError")
  }

  @ViewBuilder
  private func groupSection(
    _ group: CommandPaletteGroup, indexByID: [String: Int]
  ) -> some View {
    Text(group.localizedTitle.uppercased())
      .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, LorvexDesign.Spacing.m)
      .padding(.top, LorvexDesign.Spacing.s)

    ForEach(group.results) { result in
      resultRow(result, index: indexByID[result.id] ?? 0)
        .id(result.id)
    }
  }

  private func resultRow(_ result: CommandPaletteResult, index: Int) -> some View {
    CommandPaletteResultRow(
      result: result,
      query: query,
      isHighlighted: index == highlightedIndex,
      activate: {
        activate(result)
      },
      hover: {
        scrollsToHighlight = false
        highlightedIndex = index
      })
  }

  private func moveHighlight(_ delta: Int) {
    let count = flatResults.count
    guard count > 0 else { return }
    scrollsToHighlight = true
    highlightedIndex = (highlightedIndex + delta + count) % count
  }

  private func activateHighlighted() {
    guard flatResults.indices.contains(highlightedIndex) else { return }
    activate(flatResults[highlightedIndex])
  }

  private func activate(_ result: CommandPaletteResult) {
    switch result {
    case .navigate(let selection):
      store.navigateToWorkspace(selection)
    case .openTask(let id, _, _):
      store.selection = .tasks
      store.selectedTaskID = id
    case .createTask(let title):
      // Create from the typed title directly rather than stomping the shared
      // capture draft (read/written by Quick Capture and the menu-bar capture).
      Task { await store.createTask(title: title, notes: "") }
    case .action(let command):
      command.perform(in: store)
    }
    dismiss()
  }

  private func loadTaskResults() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      taskResults = []
      searchError = nil
      return
    }
    do {
      let results = try await store.core.searchTasks(
        query: trimmed,
        status: "all",
        limit: CommandPaletteResults.taskResultLimit,
        offset: 0)
      taskResults = results.tasks
      searchError = nil
    } catch {
      taskResults = []
      searchError = await store.userFacingBannerMessage(
        for: error, source: "macos.ui.command_palette.search_failed")
    }
  }
}
