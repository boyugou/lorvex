import LorvexCore
import SwiftUI

struct MobileTaskWorkspaceSelectableRow: View {
  let task: LorvexTask
  let isMutating: Bool
  let select: () -> Void
  let isBatchSelecting: Bool
  let isBatchSelected: Bool
  let actions: MobileTaskRowActions
  /// See ``MobileTaskRowContent/timeLabel``.
  var timeLabel: String? = nil
  /// See ``MobileTaskRowContent/isBlocked``. A blocked row offers no Start.
  var isBlocked = false
  /// The search the list is filtered by; empty outside a search. See
  /// ``LorvexTask/mobileSearchMatch(for:)``.
  var searchQuery = ""
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  private var searchMatch: LorvexTaskSearchMatch? {
    task.mobileSearchMatch(for: searchQuery)
  }

  /// What VoiceOver reads for the row: the task's own label, which names its
  /// priority, status, time, estimate, due day, and tags in words, then what
  /// the row adds to the task's fields, the search excerpt and the blocked
  /// badge. Left to itself, VoiceOver would speak the metadata's "·"
  /// separators and leave out the priority and the estimate.
  nonisolated static func spokenLabel(
    for task: LorvexTask, timeLabel: String?, isBlocked: Bool, searchMatch: LorvexTaskSearchMatch?,
    timeZone: TimeZone
  ) -> String {
    taskAccessibilityLabel(
      task, timeLabel: timeLabel,
      details: [searchMatch?.text].compactMap { $0 }
        + (isBlocked ? [MobileTaskDisplayText.blocked] : []),
      timeZone: timeZone)
  }

  private var spokenLabel: String {
    Self.spokenLabel(
      for: task, timeLabel: timeLabel, isBlocked: isBlocked, searchMatch: searchMatch,
      timeZone: productTimeZone)
  }

  var body: some View {
    rowBody
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .lorvexRowHoverEffect()
    .taskRowActions(
      task: task, actions: actions, isMutating: isMutating, isBatchSelecting: isBatchSelecting,
      isHeldUp: isBlocked)
    .accessibilityAddTraits(isBatchSelected ? [.isSelected] : [])
    .accessibilityIdentifier("mobile.tasks.selectable.\(task.id)")
  }

  /// Two layouts sharing the same row chrome:
  /// - Batch mode: the whole row is one select button led by the selection
  ///   checkbox (tapping anywhere toggles the selection). VoiceOver reads the
  ///   task, then whether it is selected; the hint says what a tap does.
  /// - Normal mode: a tappable completion circle sits beside a select button, as
  ///   sibling controls (not nested), so tapping the leading circle completes the
  ///   task while the rest of the row still opens it.
  @ViewBuilder
  private var rowBody: some View {
    if isBatchSelecting {
      Button(action: select) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          batchSelectionCheckbox
          MobileTaskRowContent(
            task: task, isBlocked: isBlocked, showsLeadingCircle: false, timeLabel: timeLabel,
            searchMatch: searchMatch, timeZone: productTimeZone)
            .equatable()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(spokenLabel)
      .accessibilityHint(selectionHint)
    } else {
      HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
        MobileTaskCompletionCircle(task: task, isMutating: isMutating, complete: actions.complete)
        Button(action: select) {
          MobileTaskRowContent(
            task: task, isBlocked: isBlocked, showsLeadingCircle: false, timeLabel: timeLabel,
            searchMatch: searchMatch, timeZone: productTimeZone)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
      }
    }
  }

  /// The checkbox is decoration: the row's `isSelected` trait carries the state.
  private var batchSelectionCheckbox: some View {
    Image(systemName: isBatchSelected ? "checkmark.circle.fill" : "circle")
      .font(.title3)
      .foregroundStyle(isBatchSelected ? Color.accentColor : .secondary)
      .mobileTaskCircleFrame(isSquare: false)
      .accessibilityHidden(true)
  }

  private var selectionHint: String {
    isBatchSelected
      ? String(
        localized: "tasks.batch.deselect", defaultValue: "Deselect task", table: "Localizable",
        bundle: MobileL10n.bundle)
      : String(
        localized: "tasks.batch.select_task", defaultValue: "Select task", table: "Localizable",
        bundle: MobileL10n.bundle)
  }
}
