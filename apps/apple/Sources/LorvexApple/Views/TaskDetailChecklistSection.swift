import LorvexCore
import SwiftUI

extension TaskDetailView {
  func checklistSection(task: LorvexTask) -> some View {
    let completedCount = task.checklistItems.filter { $0.completedAt != nil }.count
    let totalCount = task.checklistItems.count
    let completionFraction = totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)

    return InspectorPanel(accessibilityIdentifier: "task.detail.checklist.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "task_detail.checklist.title", defaultValue: "Checklist", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "checklist"
          )
          .font(LorvexDesign.Typography.primaryEmphasis)

          Spacer()

          if totalCount > 0 {
            Text("\(completedCount)/\(totalCount)")
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .padding(.horizontal, LorvexDesign.Spacing.s)
              .padding(.vertical, LorvexDesign.Spacing.xs)
              .background(.quaternary.opacity(0.35), in: Capsule())
              .accessibilityIdentifier("task.detail.checklist.count")
          }
        }

        if totalCount > 0 {
          LorvexProgressBar(value: completionFraction)
            .accessibilityIdentifier("task.detail.checklist.progress")
        }

        HStack(spacing: LorvexDesign.Spacing.s) {
          // A ghosted, non-interactive circle aligns the new-item field with the
          // rows below and reads as a not-yet-created item (you can't toggle a
          // step that doesn't exist yet).
          Image(systemName: "circle")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
          TextField(
            String(localized: "task_detail.checklist.new_placeholder", defaultValue: "New checklist item", table: "Localizable", bundle: LorvexL10n.bundle),
            text: $store.taskDetailNewChecklistText
          )
            .font(LorvexDesign.Typography.primaryText)
            .textFieldStyle(.plain)
            .frame(minWidth: 0, maxWidth: .infinity)
            .layoutPriority(1)
            .accessibilityLabel(String(localized: "task_detail.checklist.new_a11y", defaultValue: "New checklist item", table: "Localizable", bundle: LorvexL10n.bundle))
            .onSubmit {
              Task { await store.addChecklistItemToSelectedTask() }
            }
          Button {
            Task { await store.addChecklistItemToSelectedTask() }
          } label: {
            Label(
              String(localized: "task_detail.checklist.add", defaultValue: "Add", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "plus"
            )
          }
          .labelStyle(.iconOnly)
          .controlSize(.small)
          .buttonStyle(.bordered)
          .fixedSize()
          .help(String(localized: "task_detail.checklist.add_help", defaultValue: "Add checklist item", table: "Localizable", bundle: LorvexL10n.bundle))
          .disabled(
            store.taskDetailNewChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
              .isEmpty
          )
        }
        .lorvexInsetPanel(padding: LorvexDesign.Spacing.s)
        .accessibilityIdentifier(totalCount == 0 ? "task.detail.checklist.emptyInput" : "task.detail.checklist.newRow")

        if task.checklistItems.isEmpty {
          Text(LocalizedStringResource(
            "task_detail.checklist.empty",
            defaultValue: "Add the first checklist item to break this task into concrete steps.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .accessibilityIdentifier("task.detail.checklist.empty")
        }

        ForEach(task.checklistItems) { item in
          ChecklistItemRow(
            store: store,
            item: item,
            isFirst: item.id == task.checklistItems.first?.id,
            isLast: item.id == task.checklistItems.last?.id
          )
        }
      }
    }
  }
}

/// One editable checklist item: a checkbox, full-width inline text field, and a
/// hover-revealed drag handle. The row owns the visual container so the text
/// editor stays inline instead of looking like a form nested inside a card.
///
/// Reordering is drag-and-drop (grab the trailing handle) with Move Up / Move
/// Down in the right-click menu as the keyboard- and accessibility-reachable
/// fallback. Edits save automatically on Return or when the field loses focus —
/// there is no explicit save control. Delete lives in the right-click menu, not
/// a persistent trailing button, to keep the row uncluttered.
///
/// A completed item reads from the filled green check and dimmed text. It is
/// not struck through: `.strikethrough` does not reach an editable field's
/// content, and rendering the text as a `Text` until it is clicked would cost
/// inline click-to-edit and Tab traversal between items.
///
/// The text colours are explicit `Color` values, not the hierarchical
/// `.primary` / `.secondary` shape styles: inside a macOS `TextField` those two
/// resolve to the same mid-grey, which both flattened the completed state and
/// left open items below full text contrast.
private struct ChecklistItemRow: View {
  @Bindable var store: AppStore
  let item: TaskChecklistItem
  let isFirst: Bool
  let isLast: Bool
  /// Commit the edit when the field loses focus, not only on Return — clicking
  /// elsewhere should save rather than strand the draft.
  @FocusState private var isFieldFocused: Bool
  @State private var isHovering = false
  @State private var isDropTargeted = false

  /// Every item row carries the same nested-group fill, so the checklist reads
  /// as a list of rows rather than loose text under the new-item field.
  /// Completion is stated by the check and the text colour, not by the fill.
  private var rowFill: Color {
    isHovering ? LorvexDesign.Palette.hoverFill : LorvexDesign.Palette.insetFill
  }

  var body: some View {
    let draft = store.taskDetailChecklistDrafts[item.id] ?? item.text
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        Task { await store.toggleChecklistItem(item) }
      } label: {
        Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
          .contentTransition(.symbolEffect(.replace))
          .foregroundStyle(item.completedAt == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(LorvexDesign.Palette.done))
      }
      .buttonStyle(.plain)
      .help(item.completedAt == nil
        ? String(localized: "task_detail.checklist.mark_complete", defaultValue: "Mark Complete", table: "Localizable", bundle: LorvexL10n.bundle)
        : String(localized: "task_detail.checklist.mark_incomplete", defaultValue: "Mark Incomplete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(
        localized: "task_detail.checklist.item_a11y", defaultValue: "Checklist item",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
      .accessibilityValue(Text(item.completedAt == nil
        ? LocalizedStringResource("task_detail.checklist.open_a11y", defaultValue: "Not completed", table: "Localizable", bundle: LorvexL10n.bundle)
        : LocalizedStringResource("task_detail.checklist.completed_a11y", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle)))
      .accessibilityAddTraits(item.completedAt == nil ? [] : .isSelected)

      // Wrapping, not scrolling: a plain single-line field clips its overflow at
      // the frame edge with no ellipsis, so in the inspector's narrow column an
      // ordinary item such as "Confirm session topics with the facilitators"
      // was readable only by clicking into it and scrolling. The same
      // `axis: .vertical` shape carries the task title in this inspector.
      TextField(
        String(localized: "task_detail.checklist.item_placeholder", defaultValue: "Checklist item", table: "Localizable", bundle: LorvexL10n.bundle),
        text: store.checklistDraftBinding(for: item),
        axis: .vertical
      )
        .font(LorvexDesign.Typography.primaryText)
        .textFieldStyle(.plain)
        .foregroundStyle(item.completedAt == nil ? Color.primary : Color.secondary)
        .lineLimit(1...3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityLabel(String(localized: "task_detail.checklist.item_a11y", defaultValue: "Checklist item", table: "Localizable", bundle: LorvexL10n.bundle))
        .focused($isFieldFocused)
        .onSubmit {
          Task { await store.updateChecklistItem(item) }
        }
        .onChange(of: isFieldFocused) { _, focused in
          guard !focused else { return }
          Task { await store.updateChecklistItem(item) }
        }

      dragHandle(draft: draft)
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: .infinity)
    .background(rowFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .stroke(.tint, lineWidth: 1.5)
      }
    }
    .onHover { isHovering = $0 }
    .dropDestination(for: LorvexChecklistItemRef.self) { refs, _ in
      guard let draggedID = refs.first?.id else { return false }
      Task { await store.reorderChecklistItem(draggedID, toPositionOf: item.id) }
      return true
    } isTargeted: { isDropTargeted = $0 }
    .contextMenu {
      Button {
        Task { await store.moveChecklistItem(item, direction: -1) }
      } label: {
        Label(
          String(localized: "task_detail.checklist.move_up", defaultValue: "Move Up", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "chevron.up"
        )
      }
      .disabled(isFirst)

      Button {
        Task { await store.moveChecklistItem(item, direction: 1) }
      } label: {
        Label(
          String(localized: "task_detail.checklist.move_down", defaultValue: "Move Down", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "chevron.down"
        )
      }
      .disabled(isLast)

      Divider()

      Button(role: .destructive) {
        Task { await store.removeChecklistItem(item) }
      } label: {
        Label(
          String(localized: "task_detail.checklist.remove_item", defaultValue: "Remove Checklist Item", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "trash"
        )
      }
    }
  }

  /// Trailing reorder grip — visible on hover, the drag source for reordering.
  /// The drag payload is a typed `LorvexChecklistItemRef`, so only genuine
  /// checklist drags satisfy a row's `dropDestination`.
  private func dragHandle(draft: String) -> some View {
    Image(systemName: "line.3.horizontal")
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.tertiary)
      .frame(width: 18, height: 18)
      .contentShape(Rectangle())
      .opacity(isHovering ? 0.7 : 0)
      .help(String(localized: "task_detail.checklist.reorder", defaultValue: "Drag to reorder", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityHidden(true)
      .draggable(LorvexChecklistItemRef(id: item.id)) {
        Label(
          draft.isEmpty
            ? String(localized: "task_detail.checklist.item_placeholder", defaultValue: "Checklist item", table: "Localizable", bundle: LorvexL10n.bundle)
            : draft,
          systemImage: "checklist"
        )
        .font(LorvexDesign.Typography.primaryText)
        .padding(.horizontal, LorvexDesign.Spacing.s)
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      }
  }
}
