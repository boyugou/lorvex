import LorvexCore
import SwiftUI

/// Searchable list of candidate tasks for adding a dependency. Presents results
/// from `searchCandidates` (an empty query lists open tasks); tapping a row
/// calls `onSelect` and dismisses. Excluded IDs (self plus already-selected
/// dependencies) are filtered upstream by the candidate provider.
struct MobileDependencyPicker: View {
  let excludedIDs: Set<LorvexTask.ID>
  let searchCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let onSelect: (LorvexTask) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.lorvexProductTimeZone) private var productTimeZone
  @State private var query = ""
  @State private var candidates: [LorvexTask] = []
  @State private var isSearching = false

  var body: some View {
    NavigationStack {
      List {
        if isSearching, candidates.isEmpty {
          MobileSkeletonRows(count: 4)
        } else if candidates.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          // Empty query with no candidates: there simply are no other open tasks
          // to depend on. "Try a different search term" would be misleading —
          // the user hasn't searched for anything.
          ContentUnavailableView(
            String(
              localized: "dependency.no_candidates", defaultValue: "No Tasks Available",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "checklist",
            description: Text(
              String(
                localized: "dependency.no_candidates.message",
                defaultValue: "There are no other open tasks to depend on.", table: "Localizable",
                bundle: MobileL10n.bundle))
          )
        } else if candidates.isEmpty {
          ContentUnavailableView(
            String(
              localized: "dependency.no_matching_tasks", defaultValue: "No Matching Tasks",
              table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "magnifyingglass",
            description: Text(
              String(
                localized: "dependency.try_different_search",
                defaultValue: "Try a different search term.", table: "Localizable",
                bundle: MobileL10n.bundle))
          )
        } else {
          ForEach(candidates, id: \.id) { task in
            Button {
              onSelect(task)
              dismiss()
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(userContent: task.title)
                  .font(LorvexDesign.Typography.primaryText)
                  .foregroundStyle(.primary)
                if let facts = MobileDependencyFacts(task: task, timeZone: productTimeZone) {
                  facts
                }
              }
            }
            .accessibilityValue(taskDependencyAccessibilityValue(task, timeZone: productTimeZone))
          }
        }
      }
      .navigationTitle(
        String(
          localized: "dependency.add", defaultValue: "Add Dependency", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .searchable(
        text: $query,
        prompt: String(
          localized: "dependency.search_prompt", defaultValue: "Search tasks", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) { dismiss() }
        }
      }
      .task(id: query) {
        // Debounce keystrokes and drop a superseded search: `.task(id:)` cancels
        // the prior run on a new keystroke but does not await it, and the
        // provider swallows errors to `[]`, so without the guard whichever read
        // resolves last wins — an out-of-order result would show stale rows under
        // the newer query.
        guard await LorvexSearchDebounce.shouldSearch(query) else { return }
        isSearching = true
        let results = await searchCandidates(query, excludedIDs)
        guard !Task.isCancelled else { return }
        candidates = results
        isSearching = false
      }
    }
  }
}
