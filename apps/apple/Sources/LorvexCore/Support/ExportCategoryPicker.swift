import SwiftUI

/// Shared category selector for the data-export surfaces on macOS and iOS. Renders
/// one `Toggle` per `LorvexDataExportCategory` bound to `selection`, plus "Select
/// All" / "Select None" shortcuts. Each toggle carries an accessibility identifier
/// of the form `\(idPrefix).category.\(category.rawValue)` so surface-specific UI
/// tests keep their existing selectors (`dataExport.*` on macOS,
/// `mobileDataExport.*` on iOS).
public struct ExportCategoryPicker: View {
  @Binding private var selection: Set<LorvexDataExportCategory>
  private let idPrefix: String
  private let categoryName: (LorvexDataExportCategory) -> String
  private let selectAllLabel: String
  private let selectNoneLabel: String

  /// `LorvexCore` carries no string catalog, so each host injects the localized
  /// category names and button labels. The defaults are the English source so
  /// the picker stays self-contained for previews and tests.
  public init(
    selection: Binding<Set<LorvexDataExportCategory>>,
    idPrefix: String,
    categoryName: @escaping (LorvexDataExportCategory) -> String = { $0.displayLabel },
    selectAllLabel: String = "Select All",
    selectNoneLabel: String = "Select None"
  ) {
    self._selection = selection
    self.idPrefix = idPrefix
    self.categoryName = categoryName
    self.selectAllLabel = selectAllLabel
    self.selectNoneLabel = selectNoneLabel
  }

  public var body: some View {
    ForEach(LorvexDataExportCategory.allCases) { category in
      Toggle(
        categoryName(category),
        isOn: Binding(
          get: { selection.contains(category) },
          set: { isOn in
            if isOn {
              selection.insert(category)
            } else {
              selection.remove(category)
            }
          }
        )
      )
      .accessibilityIdentifier("\(idPrefix).category.\(category.rawValue)")
    }

    HStack {
      Button(selectAllLabel) {
        selection = Set(LorvexDataExportCategory.allCases)
      }
      .disabled(selection.count == LorvexDataExportCategory.allCases.count)
      Button(selectNoneLabel) {
        selection.removeAll()
      }
      .disabled(selection.isEmpty)
    }
    .font(.caption)
  }
}
