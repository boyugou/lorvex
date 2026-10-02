import SwiftUI

/// The data-export category selector as form sections: one section per group
/// (``LorvexDataExportCategory/Group``) with a switch row per category, each
/// with its symbol, bound to `selection`. One plain accent button in the first
/// section's header selects every category, or, once all are selected, clears
/// them. Each toggle carries the identifier
/// `\(idPrefix).category.\(category.rawValue)` and the button
/// `\(idPrefix).selectAll`.
public struct ExportCategoryPicker: View {
  @Binding private var selection: Set<LorvexDataExportCategory>
  private let idPrefix: String
  private let selectAllLabel: String
  private let selectNoneLabel: String

  /// The category and group names come from LorvexCore's catalog; the host
  /// supplies the button's two labels in its own words.
  public init(
    selection: Binding<Set<LorvexDataExportCategory>>,
    idPrefix: String,
    selectAllLabel: String,
    selectNoneLabel: String
  ) {
    self._selection = selection
    self.idPrefix = idPrefix
    self.selectAllLabel = selectAllLabel
    self.selectNoneLabel = selectNoneLabel
  }

  public var body: some View {
    ForEach(LorvexDataExportCategory.Group.allCases) { group in
      Section {
        ForEach(group.categories) { category in
          toggle(category)
        }
      } header: {
        HStack(alignment: .firstTextBaseline) {
          Text(group.localizedName)
          Spacer(minLength: LorvexDesign.Spacing.s)
          if group == LorvexDataExportCategory.Group.allCases.first {
            selectButton.textCase(nil)
          }
        }
      }
    }
  }

  private var allSelected: Bool {
    selection.count == LorvexDataExportCategory.allCases.count
  }

  private var selectButton: some View {
    Button(allSelected ? selectNoneLabel : selectAllLabel) {
      selection = allSelected ? [] : Set(LorvexDataExportCategory.allCases)
    }
    .buttonStyle(.plain)
    .font(LorvexDesign.Typography.secondaryText)
    .foregroundStyle(LorvexDesign.Palette.accent)
    .accessibilityIdentifier("\(idPrefix).selectAll")
  }

  private func isOn(_ category: LorvexDataExportCategory) -> Binding<Bool> {
    Binding(
      get: { selection.contains(category) },
      set: { isOn in
        if isOn {
          selection.insert(category)
        } else {
          selection.remove(category)
        }
      })
  }

  private func toggle(_ category: LorvexDataExportCategory) -> some View {
    Toggle(isOn: isOn(category)) {
      Label(category.localizedDisplayName, systemImage: category.systemImage)
    }
    .accessibilityIdentifier("\(idPrefix).category.\(category.rawValue)")
  }
}
