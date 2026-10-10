import LorvexCore
import SwiftUI

/// Dependency entry for the task editors: each current dependency is a list
/// row with the task's title and a remove control, and a last row, "Add
/// Dependency", presents a searchable picker of candidate tasks. The rows are
/// direct children of the hosting `Section`, so each takes the list's own row
/// height and separator, and the field belongs in a `List` or `Form` section.
/// Binds to an ordered list of dependency task IDs; titles are resolved
/// through `resolveTitles`.
struct MobileDependencyField: View {
  @Binding var dependencyIDs: [LorvexTask.ID]
  let ownTaskID: LorvexTask.ID
  let searchCandidates: (String, Set<LorvexTask.ID>) async -> [LorvexTask]
  let resolveTitles: ([LorvexTask.ID]) async -> [LorvexTask]

  @State private var resolved: [LorvexTask] = []
  @State private var isPickerPresented = false
  /// The column the row glyphs sit in, grown with the body style they are set
  /// in, so titles and the add label share one leading edge at every text size.
  @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 22
  /// How far the remove control's tap target reaches past its glyph on each
  /// side, which makes it 44 pt across at the default text size. The control
  /// pads its label by this much, gives it a rectangular content shape, and
  /// takes the padding back with a negative padding outside the button, so the
  /// row is laid out around the glyph's own size.
  private static let removeTapOutset: CGFloat = 13

  var body: some View {
    Group {
      ForEach(dependencyIDs, id: \.self) { id in
        HStack(spacing: LorvexDesign.Spacing.m) {
          Image(systemName: "arrow.triangle.branch")
            .foregroundStyle(.secondary)
            .frame(width: glyphWidth)
            .accessibilityHidden(true)
          Text(userContent: title(for: id))
            .font(LorvexDesign.Typography.primaryText)
            .lineLimitUnlessAccessibilitySize(2)
          Spacer(minLength: LorvexDesign.Spacing.s)
          removeButton(for: id)
        }
      }
      addButton
    }
  }

  private func removeButton(for id: LorvexTask.ID) -> some View {
    Button {
      remove(id)
    } label: {
      // A plain color, not the hierarchical `.secondary` style: inside a
      // borderless button that style takes its level from the button's accent
      // tint and draws a faint blue disc instead of gray.
      Image(systemName: "minus.circle.fill")
        .foregroundStyle(Color.secondary)
        .padding(Self.removeTapOutset)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .padding(-Self.removeTapOutset)
    .accessibilityLabel(
      String(
        format: String(
          localized: "dependency.remove.a11y", defaultValue: "Remove dependency %@",
          table: "Localizable", bundle: MobileL10n.bundle), title(for: id)))
  }

  /// The last row. It also carries the title lookup and the picker sheet, which
  /// belong to the field as a whole and must attach to exactly one row.
  private var addButton: some View {
    Button {
      isPickerPresented = true
    } label: {
      HStack(spacing: LorvexDesign.Spacing.m) {
        Image(systemName: "plus.circle")
          .frame(width: glyphWidth)
          .accessibilityHidden(true)
        Text(
          String(
            localized: "dependency.add", defaultValue: "Add Dependency", table: "Localizable",
            bundle: MobileL10n.bundle))
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
