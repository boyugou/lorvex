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
  @State private var query = ""
  @State private var candidates: [LorvexTask] = []
  @State private var isSearching = false

  var body: some View {
    NavigationStack {
      List {
        if isSearching, candidates.isEmpty {
          MobileSkeletonRows(count: 4)
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
                Text(task.title)
                  .font(LorvexDesign.Typography.primaryText)
                  .foregroundStyle(.primary)
                Text(MobileTaskDisplayText.compactPriorityAndStatus(priority: task.priority, status: task.status))
                  .font(LorvexDesign.Typography.tertiaryText)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      .navigationTitle(
        String(
          localized: "dependency.add", defaultValue: "Add Dependency", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS) || os(visionOS)
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
        isSearching = true
        candidates = await searchCandidates(query, excludedIDs)
        isSearching = false
      }
    }
  }
}
