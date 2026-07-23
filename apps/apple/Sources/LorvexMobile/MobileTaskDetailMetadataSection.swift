import LorvexCore
import SwiftUI

struct MobileTaskDetailMetadataSection: View {
  let task: LorvexTask
  /// Resolves dependency task IDs to their tasks so "Depends On" reads as titles,
  /// not raw IDs. When absent (previews), the section falls back to the IDs.
  var resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])?

  @State private var resolvedDependencies: [LorvexTask] = []

  var body: some View {
    // Priority / status / planned / estimate are carried by the detail header's
    // glance chips, so this section holds only what the chips don't — and hides
    // entirely when there's nothing extra to show.
    if hasExtraDetails {
      Section(
        String(
          localized: "task_detail.section.details", defaultValue: "Details", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        if !task.tags.isEmpty {
          LabeledContent(
            String(
              localized: "task_detail.tags", defaultValue: "Tags", table: "Localizable",
              bundle: MobileL10n.bundle), value: task.tags.joined(separator: ", "))
        }
        if !task.dependsOn.isEmpty {
          LabeledContent(
            String(
              localized: "task_detail.depends_on", defaultValue: "Depends On", table: "Localizable",
              bundle: MobileL10n.bundle), value: dependencySummary)
        }
        if let latenessState = task.latenessState, !latenessState.isEmpty {
          LabeledContent(
            String(
              localized: "task_detail.lateness", defaultValue: "Lateness", table: "Localizable",
              bundle: MobileL10n.bundle),
            value: MobileTaskDisplayText.latenessState(latenessState))
        }
        if let recurrence = task.recurrence {
          LabeledContent(
            String(
              localized: "task_detail.repeats", defaultValue: "Repeats", table: "Localizable",
              bundle: MobileL10n.bundle),
            value: recurrence.displaySummary(exceptions: task.recurrenceExceptions)
          )
        }
      }
      .task(id: task.dependsOn) {
        guard !task.dependsOn.isEmpty, let resolveDependencyTasks else { return }
        resolvedDependencies = await resolveDependencyTasks(task.dependsOn)
      }
    }
  }

  /// Dependency titles joined for display; a dangling ID (its task no longer
  /// exists) degrades to the raw ID, matching the edit surface's picker rows.
  private var dependencySummary: String {
    task.dependsOn
      .map { id in resolvedDependencies.first(where: { $0.id == id })?.title ?? id }
      .joined(separator: ", ")
  }

  private var hasExtraDetails: Bool {
    !task.tags.isEmpty
      || !task.dependsOn.isEmpty
      || !(task.latenessState ?? "").isEmpty
      || task.recurrence != nil
  }
}
