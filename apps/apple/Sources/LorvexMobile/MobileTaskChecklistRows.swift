import LorvexCore
import SwiftUI

/// A started task opens at the remaining work. Finished steps stay in their
/// original order behind a disclosure so they can still be read or reopened.
struct MobileTaskChecklistRows: View {
  let task: LorvexTask
  let isMutating: Bool
  let toggle: ((TaskChecklistItem) async -> Void)?
  let remove: ((TaskChecklistItem) async -> Void)?
  @State private var showsCompleted = false

  var body: some View {
    let steps = task.checklistItems.sorted { $0.position < $1.position }
    if task.status == .inProgress {
      rows(steps.filter { $0.completedAt == nil })
      let completed = steps.filter { $0.completedAt != nil }
      if !completed.isEmpty {
        DisclosureGroup(isExpanded: $showsCompleted) {
          rows(completed)
        } label: {
          HStack {
            Text(String(localized: "task.row.completed.a11y", defaultValue: "Completed",
              table: "Localizable", bundle: MobileL10n.bundle))
            Spacer()
            Text(completed.count, format: .number).monospacedDigit()
          }
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("task.detail.checklist.completed")
        }
      }
    } else {
      rows(steps)
    }
  }

  private func rows(_ steps: [TaskChecklistItem]) -> some View {
    ForEach(steps) { step in
      MobileChecklistItemRow(item: step, toggleChecklistItem: toggle, removeChecklistItem: remove)
        .disabled(isMutating)
    }
  }
}
