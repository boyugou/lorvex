import LorvexCore
import SwiftUI

struct MobileTaskWorkspaceSelectableRow: View {
  let task: LorvexTask
  let isFocused: Bool
  let isMutating: Bool
  let select: () -> Void
  let isBatchSelecting: Bool
  let isBatchSelected: Bool
  let toggleFocus: () async -> Void
  let complete: () async -> Void
  let deferTask: () async -> Void

  var body: some View {
    rowBody
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .lorvexRowHoverEffect()
    .taskRowActions(
      task: task,
      isFocused: isFocused,
      isMutating: isMutating,
      isBatchSelecting: isBatchSelecting,
      toggleFocus: toggleFocus,
      complete: complete,
      deferTask: deferTask)
    .accessibilityAddTraits(isBatchSelected ? [.isSelected] : [])
    .accessibilityIdentifier("mobile.tasks.selectable.\(task.id)")
  }

  /// Two layouts sharing the same row chrome:
  /// - Batch mode: the whole row is one select button led by the selection
  ///   checkbox (tapping anywhere toggles the selection).
  /// - Normal mode: a tappable completion circle sits beside a select button, as
  ///   sibling controls (not nested), so tapping the leading circle completes the
  ///   task while the rest of the row still opens it.
  @ViewBuilder
  private var rowBody: some View {
    if isBatchSelecting {
      Button(action: select) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          batchSelectionCheckbox
          MobileTaskRowContent(task: task, isFocused: isFocused, showsLeadingCircle: false)
            .equatable()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
        MobileTaskCompletionCircle(task: task, isMutating: isMutating, complete: complete)
        Button(action: select) {
          MobileTaskRowContent(task: task, isFocused: isFocused, showsLeadingCircle: false)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var batchSelectionCheckbox: some View {
    Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
      .font(.title3)
      .foregroundStyle(isBatchSelected ? Color.accentColor : .secondary)
      .frame(width: 26)
      .accessibilityLabel(
        isBatchSelected
          ? String(
            localized: "tasks.batch.deselect", defaultValue: "Deselect task", table: "Localizable",
            bundle: MobileL10n.bundle)
          : String(
            localized: "tasks.batch.select_task", defaultValue: "Select task", table: "Localizable",
            bundle: MobileL10n.bundle)
      )
  }
}
