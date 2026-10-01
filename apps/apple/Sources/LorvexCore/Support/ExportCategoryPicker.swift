import SwiftUI

/// How ``ExportCategoryPicker`` lays out its categories: a form section per
/// group with one switch row per category (`sections`, the phone form), or a
/// labeled line of checkboxes per group inside the caller's section (`grid`,
/// the Mac settings form, where ten switch rows would push the export actions
/// below the first screen).
public enum ExportCategoryPickerLayout: Sendable {
  case sections
  case grid
}

/// Shared category selector for the data-export surfaces on macOS and iOS: the
/// categories under their groups (``LorvexDataExportCategory/Group``), each
/// with its symbol, bound to `selection`. One plain accent button at the top
/// selects every category, or, once all are selected, clears them. Each toggle
/// carries the identifier `\(idPrefix).category.\(category.rawValue)` and the
/// button `\(idPrefix).selectAll`, so each surface keeps its own prefix
/// (`dataExport` on macOS, `mobileDataExport` on iOS).
public struct ExportCategoryPicker: View {
  @Binding private var selection: Set<LorvexDataExportCategory>
  private let idPrefix: String
  private let layout: ExportCategoryPickerLayout
  private let categoryName: (LorvexDataExportCategory) -> String
  private let groupName: (LorvexDataExportCategory.Group) -> String
  private let selectAllLabel: String
  private let selectNoneLabel: String

  /// `LorvexCore` carries no string catalog, so each host injects the localized
  /// category and group names and the button's two labels.
  public init(
    selection: Binding<Set<LorvexDataExportCategory>>,
    idPrefix: String,
    layout: ExportCategoryPickerLayout,
    categoryName: @escaping (LorvexDataExportCategory) -> String,
    groupName: @escaping (LorvexDataExportCategory.Group) -> String,
    selectAllLabel: String,
    selectNoneLabel: String
  ) {
    self._selection = selection
    self.idPrefix = idPrefix
    self.layout = layout
    self.categoryName = categoryName
    self.groupName = groupName
    self.selectAllLabel = selectAllLabel
    self.selectNoneLabel = selectNoneLabel
  }

  public var body: some View {
    switch layout {
    case .sections:
      ForEach(LorvexDataExportCategory.Group.allCases) { group in
        Section {
          ForEach(group.categories) { category in
            toggle(category)
          }
        } header: {
          HStack(alignment: .firstTextBaseline) {
            Text(groupName(group))
            Spacer(minLength: LorvexDesign.Spacing.s)
            if group == LorvexDataExportCategory.Group.allCases.first {
              selectButton.textCase(nil)
            }
          }
        }
      }
    case .grid:
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        ForEach(LorvexDataExportCategory.Group.allCases) { group in
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
              Text(groupName(group))
                .font(LorvexDesign.Typography.tertiaryText)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
              Spacer(minLength: LorvexDesign.Spacing.s)
              if group == LorvexDataExportCategory.Group.allCases.first {
                selectButton
              }
            }
            LorvexFlowLayout(spacing: LorvexDesign.Spacing.l, lineSpacing: LorvexDesign.Spacing.xs) {
              ForEach(group.categories) { category in
                gridToggle(category)
              }
            }
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
      Label(categoryName(category), systemImage: category.systemImage)
    }
    .accessibilityIdentifier("\(idPrefix).category.\(category.rawValue)")
  }

  /// A grid cell reads as a checkbox with its symbol and name beside it; the
  /// checkbox style only exists on the Mac, so other platforms keep the plain
  /// toggle. The label is an explicit stack, since a `Label` placed by
  /// ``LorvexFlowLayout`` draws only its icon.
  @ViewBuilder
  private func gridToggle(_ category: LorvexDataExportCategory) -> some View {
    let cell = Toggle(isOn: isOn(category)) {
      HStack(spacing: LorvexDesign.Spacing.xxs) {
        Image(systemName: category.systemImage)
          .foregroundStyle(.secondary)
          .frame(minWidth: 18)
        Text(categoryName(category))
          .fixedSize()
      }
    }
    .accessibilityIdentifier("\(idPrefix).category.\(category.rawValue)")
    #if os(macOS)
      cell.toggleStyle(.checkbox)
    #else
      cell
    #endif
  }
}
