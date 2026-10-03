import LorvexCore
import SwiftUI

/// One set field of the item an inspector shows (a task, a habit), drawn as
/// a row of its properties.
struct InspectorPropertyRow: Identifiable {
  let id: String
  let systemImage: String
  let label: String
  let value: String
  /// A state color for the value and its icon (an overdue deadline, a high
  /// priority); nil draws the value in the primary style.
  var tint: Color? = nil
  /// The value is text the user wrote, such as a task's title, rather than
  /// the app's words: it is typeset by the rules of its own script and kept
  /// to two lines.
  var isUserContent = false
}

/// A field the item does not carry yet, offered as a dashed "+ Field" capsule.
struct InspectorPropertyAddition: Identifiable {
  let id: String
  let label: String
}

/// An inspector's fields as rows, one per set field: an icon, the field's
/// name in the secondary style, and its value. Clicking a row (or a dashed
/// addition for a field the item does not carry yet) opens that one field's
/// editor. The task and habit inspectors share it, so a field reads and edits
/// the same way in both.
///
/// Most fields open their editor in a popover (`editor`). A field whose ids
/// are in `menuFieldIDs` opens a native menu instead (`menuItems`), for a
/// short fixed set of choices such as priority; such a menu may also offer a
/// "Custom…" item that calls its `openEditor` argument to show the popover.
/// The caller supplies values that reflect edits as they are made, so a row
/// shows its new value while its editor is still open. An edit that sets an
/// added field or clears a set one moves it between the additions and the
/// rows; the field keeps its control as it moves, so its editor stays open on
/// it. A popover editor that saves on close does so from its own
/// `onDisappear`, which runs when the popover closes.
///
/// `idPrefix` starts every accessibility identifier: `<prefix>.properties`
/// for the whole group, `<prefix>.row.<field id>` for a row, and
/// `<prefix>.addField.<field id>` for an addition.
struct InspectorProperties<Editor: View, MenuItems: View>: View {
  let rows: [InspectorPropertyRow]
  let additions: [InspectorPropertyAddition]
  let idPrefix: String
  var menuFieldIDs: Set<String> = []
  @ViewBuilder var editor: (String) -> Editor
  @ViewBuilder var menuItems: (_ id: String, _ openEditor: @escaping () -> Void) -> MenuItems

  @State private var editingID: String?
  @ScaledMetric(relativeTo: .callout) private var labelWidth: CGFloat = 84

  /// The rows, then the additions, in one sequence keyed by field id, so a
  /// field that moves between the two keeps its control and the popover it
  /// anchors.
  private var fields: [Field] {
    rows.map(Field.row) + additions.map(Field.addition)
  }

  var body: some View {
    InspectorPropertiesLayout(
      sectionSpacing: LorvexDesign.Spacing.s,
      additionSpacing: LorvexDesign.Spacing.xs,
      additionInset: LorvexDesign.Spacing.xs
    ) {
      ForEach(fields) { field in
        control(field.id) { isActive in
          switch field {
          case .row(let row): rowLabel(row, isActive: isActive)
          case .addition(let addition): additionLabel(addition)
          }
        }
        .layoutValue(key: InspectorPropertyIsRow.self, value: field.isRow)
        .accessibilityIdentifier(
          field.isRow ? "\(idPrefix).row.\(field.id)" : "\(idPrefix).addField.\(field.id)")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("\(idPrefix).properties")
    .reduceMotionAnimation(.snappy(duration: 0.25), value: rows.map(\.id))
  }

  /// The control behind a row or an addition: a menu for the menu fields, a
  /// button that opens the popover editor for the rest. Both anchor the
  /// popover, so a menu's "Custom…" item opens it in place.
  @ViewBuilder
  private func control<Label: View>(_ id: String, @ViewBuilder label: @escaping (Bool) -> Label) -> some View {
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
        .environment(\.inspectorPanelInPopover, true)
    }
  }

  private func rowLabel(_ row: InspectorPropertyRow, isActive: Bool) -> some View {
    InspectorPropertyRowLabel(row: row, labelWidth: labelWidth, isActive: isActive)
  }

  private func additionLabel(_ addition: InspectorPropertyAddition) -> some View {
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

extension InspectorProperties {
  /// One field as the properties show it: a row while set, an addition
  /// while not.
  private enum Field: Identifiable {
    case row(InspectorPropertyRow)
    case addition(InspectorPropertyAddition)

    var id: String {
      switch self {
      case .row(let row): row.id
      case .addition(let addition): addition.id
      }
    }

    var isRow: Bool {
      if case .row = self { true } else { false }
    }
  }
}

/// Whether a subview of ``InspectorPropertiesLayout`` is a row; the rest are
/// additions.
private struct InspectorPropertyIsRow: LayoutValueKey {
  static let defaultValue = false
}

/// The properties' arrangement: the rows stacked at the full width, then,
/// `sectionSpacing` below them, the additions flowing in lines
/// (``LorvexFlowLayout``) inset by `additionInset`. The rows come before the
/// additions among the subviews.
private struct InspectorPropertiesLayout: Layout {
  let sectionSpacing: CGFloat
  let additionSpacing: CGFloat
  let additionInset: CGFloat

  private var flow: LorvexFlowLayout {
    LorvexFlowLayout(spacing: additionSpacing, lineSpacing: additionSpacing, fillsWidth: true)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let (rows, additions) = split(subviews)
    let rowSizes = rows.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
    var flowCache: Void = ()
    let flowSize = additions.isEmpty
      ? .zero
      : flow.sizeThatFits(
        proposal: ProposedViewSize(width: proposal.width.map { max($0 - additionInset, 0) }, height: nil),
        subviews: additions, cache: &flowCache)
    let rowsHeight = rowSizes.reduce(0) { $0 + $1.height }
    let gap = rows.isEmpty || additions.isEmpty ? 0 : sectionSpacing
    let width = proposal.width
      ?? max(rowSizes.map(\.width).max() ?? 0, additions.isEmpty ? 0 : flowSize.width + additionInset)
    return CGSize(width: width, height: rowsHeight + gap + flowSize.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    let (rows, additions) = split(subviews)
    let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
    var y = bounds.minY
    for row in rows {
      row.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: rowProposal)
      y += row.sizeThatFits(rowProposal).height
    }
    guard !additions.isEmpty else { return }
    if !rows.isEmpty { y += sectionSpacing }
    let flowProposal = ProposedViewSize(width: max(bounds.width - additionInset, 0), height: nil)
    var flowCache: Void = ()
    let flowSize = flow.sizeThatFits(proposal: flowProposal, subviews: additions, cache: &flowCache)
    flow.placeSubviews(
      in: CGRect(x: bounds.minX + additionInset, y: y, width: flowSize.width, height: flowSize.height),
      proposal: flowProposal, subviews: additions, cache: &flowCache)
  }

  private func split(_ subviews: Subviews) -> (rows: Subviews, additions: Subviews) {
    let boundary = subviews.firstIndex { !$0[InspectorPropertyIsRow.self] } ?? subviews.endIndex
    return (subviews[subviews.startIndex..<boundary], subviews[boundary..<subviews.endIndex])
  }
}

extension InspectorProperties where MenuItems == EmptyView {
  /// Properties whose every field opens a popover editor.
  init(
    rows: [InspectorPropertyRow],
    additions: [InspectorPropertyAddition],
    idPrefix: String,
    @ViewBuilder editor: @escaping (String) -> Editor
  ) {
    self.init(
      rows: rows, additions: additions, idPrefix: idPrefix, editor: editor,
      menuItems: { _, _ in EmptyView() })
  }
}

/// A property row's face: the icon, the field name, and the value, on a
/// surface that fills faintly under the pointer and while its editor is open.
private struct InspectorPropertyRowLabel: View {
  let row: InspectorPropertyRow
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
      (row.isUserContent ? Text(userContent: row.value) : Text(row.value))
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(row.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
        .lineLimit(row.isUserContent ? 2 : nil)
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
