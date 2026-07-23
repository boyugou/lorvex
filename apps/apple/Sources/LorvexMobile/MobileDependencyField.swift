import LorvexCore
import SwiftUI

/// Dependency entry for the task editor: current dependencies render as
/// removable rows showing each task's title, and an "Add dependency" control
/// presents a searchable picker of candidate tasks. Binds to an ordered list of
/// dependency task IDs; titles are resolved through `resolveTitles`.
struct MobileDependencyField: View {
  @Binding var dependencyIDs: [LorvexTask.ID]
  let ownTaskID: LorvexTask.ID
  let searchCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let resolveTitles: ([LorvexTask.ID]) async -> [LorvexTask]

  @State private var resolved: [LorvexTask] = []
  @State private var isPickerPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(dependencyIDs, id: \.self) { id in
        HStack(spacing: 8) {
          Image(systemName: "arrow.triangle.branch")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
          Text(title(for: id))
            .font(LorvexDesign.Typography.primaryText)
            .lineLimit(2)
          Spacer(minLength: 8)
          Button {
            remove(id)
          } label: {
            Image(systemName: "minus.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            String(
              format: String(
                localized: "dependency.remove.a11y", defaultValue: "Remove dependency %@",
                table: "Localizable", bundle: MobileL10n.bundle), title(for: id)))
        }
      }

      Button {
        isPickerPresented = true
      } label: {
        Label(
          String(
            localized: "dependency.add", defaultValue: "Add Dependency", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle")
      }
    }
    .task(id: dependencyIDs) {
      resolved = await resolveTitles(dependencyIDs)
    }
    .sheet(isPresented: $isPickerPresented) {
      MobileDependencyPicker(
        excludedIDs: Set(dependencyIDs).union([ownTaskID]),
        searchCandidates: searchCandidates
      ) { task in
        add(task)
      }
      .lorvexSpatialBackground()
      .mobileCompactEditorSheetPresentation()
    }
  }

  private func title(for id: LorvexTask.ID) -> String {
    resolved.first(where: { $0.id == id })?.title ?? id
  }

  private func add(_ task: LorvexTask) {
    guard !dependencyIDs.contains(task.id) else { return }
    dependencyIDs.append(task.id)
    if !resolved.contains(where: { $0.id == task.id }) {
      resolved.append(task)
    }
  }

  private func remove(_ id: LorvexTask.ID) {
    dependencyIDs.removeAll { $0 == id }
  }
}
