import LorvexCore
import SwiftUI

/// The tasks a task waits on under "Waits On", one task row per task: its
/// completion circle, which checks the blocker off like every task row's, its
/// title, and whether it has been started and when it is due
/// (``MobileDependencyFacts``), opening that task's detail. Whether a blocker
/// is done or on its way is a glance away, finishing it a tap away, and its
/// detail a tap away. The section hides when the task waits on nothing; the
/// property sentence above then offers "+ Waits on".
struct MobileTaskDependenciesSection: View {
  let task: LorvexTask
  /// Resolves dependency task IDs to their tasks so the rows read as titles,
  /// not raw IDs. When absent (previews), the rows show the IDs.
  var resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])?
  /// Completes a dependency. When absent (previews), the circle is the task's
  /// status glyph alone.
  var completeDependency: ((LorvexTask) async -> Void)?
  /// Whether a mutation of that dependency is in flight, which disables its
  /// circle.
  var isDependencyMutating: (LorvexTask.ID) -> Bool = { _ in false }

  /// The resolved dependencies, `nil` until the first resolution lands.
  @State private var resolvedDependencies: [LorvexTask]?
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    if !task.dependsOn.isEmpty {
      Section(
        String(
          localized: "task_detail.waits_on", defaultValue: "Waits On", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        ForEach(task.dependsOn, id: \.self) { id in
          if let dependency = resolvedDependencies?.first(where: { $0.id == id }) {
            if let completeDependency {
              HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
                MobileTaskCompletionCircle(
                  task: dependency, isMutating: isDependencyMutating(dependency.id)
                ) {
                  await completeDependency(dependency)
                  await resolve()
                }
                dependencyLink(dependency)
              }
            } else {
              dependencyLink(dependency)
            }
          } else {
            // A placeholder until the titles resolve, so a raw ID never shows
            // for a task that still exists; a dangling ID (its task no longer
            // exists) then reads as the raw ID, matching the edit surface's
            // picker rows, and opens nothing.
            Text(id)
              .foregroundStyle(.secondary)
              .redacted(reason: isResolving ? .placeholder : [])
          }
        }
      }
      .task(id: task.dependsOn) {
        await resolve()
      }
    }
  }

  /// The row's title and facts, opening the dependency's detail. Without a
  /// completion circle beside it, the status glyph leads the title instead,
  /// on its first line as on a task row.
  private func dependencyLink(_ dependency: LorvexTask) -> some View {
    NavigationLink(value: MobileRoute.task(dependency.id)) {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        if completeDependency == nil {
          Image(systemName: dependency.statusCircleGlyph)
            .foregroundStyle(dependency.statusCircleStyle)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(userContent: dependency.title)
            .foregroundStyle(dependency.status.isResolved ? .secondary : .primary)
          if let facts = MobileDependencyFacts(task: dependency, timeZone: productTimeZone) {
            facts
          }
        }
      }
      .padding(.top, completeDependency == nil ? 0 : LorvexDesign.Spacing.xs)
    }
    .accessibilityValue(taskDependencyAccessibilityValue(dependency, timeZone: productTimeZone))
    .accessibilityIdentifier("task.detail.waitsOn.row")
  }

  /// Reads the dependencies' current tasks, on first appearance and again
  /// after one is completed so its circle and facts show the new status.
  private func resolve() async {
    guard let resolveDependencyTasks else { return }
    resolvedDependencies = await resolveDependencyTasks(task.dependsOn)
  }

  private var isResolving: Bool {
    resolveDependencyTasks != nil && resolvedDependencies == nil
  }
}
