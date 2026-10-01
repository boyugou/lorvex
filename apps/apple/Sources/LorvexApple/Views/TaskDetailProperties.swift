import LorvexCore
import SwiftUI

/// One set field of a task, shown as a row of the task detail.
struct TaskDetailPropertyRow: Identifiable {
  let id: String
  let systemImage: String
  let label: String
  let value: String
  /// A state color for the value and its icon (an overdue deadline, a high
  /// priority); nil draws the value in the primary style.
  var tint: Color? = nil
}

/// A field the task does not carry yet, offered as a dashed "+ Field" capsule.
struct TaskDetailPropertyAddition: Identifiable {
  let id: String
  let label: String
}

/// The task's fields as rows, one per set field: an icon, the field's name in
/// the secondary style, and its value. Clicking a row (or a dashed addition
/// for a field the task does not carry yet) opens that one field's editor.
///
/// Most fields open their editor in a popover (`editor`). A field whose ids
/// are in `menuFieldIDs` opens a native menu instead (`menuItems`), for a
/// short fixed set of choices such as priority; such a menu may also offer a
/// "Custom…" item that calls its `openEditor` argument to show the popover.
/// Values come from the draft summaries, so an edit shows in its row as soon
/// as it is made.
struct TaskDetailProperties<Editor: View, MenuItems: View>: View {
  let rows: [TaskDetailPropertyRow]
  let additions: [TaskDetailPropertyAddition]
  var menuFieldIDs: Set<String> = []
  @ViewBuilder var editor: (String) -> Editor
  @ViewBuilder var menuItems: (_ id: String, _ openEditor: @escaping () -> Void) -> MenuItems

  @State private var editingID: String?
  @ScaledMetric(relativeTo: .callout) private var labelWidth: CGFloat = 84

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      if !rows.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(rows) { row in
            field(row.id) { isActive in rowLabel(row, isActive: isActive) }
              .accessibilityIdentifier("task.detail.row.\(row.id)")
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task.detail.properties")
      }
      if !additions.isEmpty {
        LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs, fillsWidth: true) {
          ForEach(additions) { addition in
            field(addition.id) { _ in additionLabel(addition) }
              .accessibilityIdentifier("task.detail.addField.\(addition.id)")
          }
        }
        .padding(.leading, LorvexDesign.Spacing.xs)
        .accessibilityIdentifier("task.detail.additions")
      }
    }
  }

  /// The control behind a row or an addition: a menu for the menu fields, a
  /// button that opens the popover editor for the rest. Both anchor the
  /// popover, so a menu's "Custom…" item opens it in place.
  @ViewBuilder
  private func field<Label: View>(_ id: String, @ViewBuilder label: @escaping (Bool) -> Label) -> some View {
    Group {
      if menuFieldIDs.contains(id) {
        Menu {
          menuItems(id) { editingID = id }
        } label: {
          label(editingID == id)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
      } else {
        Button {
          editingID = id
        } label: {
          label(editingID == id)
        }
        .buttonStyle(.plain)
      }
    }
    .popover(isPresented: presentation(for: id), arrowEdge: .leading) {
      editor(id)
        .padding(LorvexDesign.Spacing.m)
        .frame(minWidth: 280)
        .background(.windowBackground)
        .environment(\.taskDetailPanelInPopover, true)
    }
  }

  private func rowLabel(_ row: TaskDetailPropertyRow, isActive: Bool) -> some View {
    TaskDetailPropertyRowLabel(row: row, labelWidth: labelWidth, isActive: isActive)
  }

  private func additionLabel(_ addition: TaskDetailPropertyAddition) -> some View {
    HStack(spacing: LorvexDesign.Spacing.xxs) {
      Image(systemName: "plus").imageScale(.small)
      Text(addition.label).fixedSize()
    }
    .font(LorvexDesign.Typography.secondaryText)
    .foregroundStyle(.secondary)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .overlay(
      Capsule().strokeBorder(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    )
    .contentShape(Capsule())
  }

  private func presentation(for id: String) -> Binding<Bool> {
    Binding(
      get: { editingID == id },
      set: { if !$0, editingID == id { editingID = nil } })
  }
}

/// A property row's face: the icon, the field name, and the value, on a
/// surface that fills faintly under the pointer and while its editor is open.
private struct TaskDetailPropertyRowLabel: View {
  let row: TaskDetailPropertyRow
  let labelWidth: CGFloat
  let isActive: Bool

  @State private var isHovering = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: row.systemImage)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(row.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        .frame(width: 18)
      Text(row.label)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: labelWidth, alignment: .leading)
      Text(row.value)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(row.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, LorvexDesign.Spacing.xs)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous)
        .fill(.quaternary.opacity(isActive ? 1 : isHovering ? 0.6 : 0)))
    .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }
}
