import LorvexCore
import SwiftUI

/// Shared multi-select building blocks for the simple catalog workspaces
/// (Lists / Memory / Habits): the bottom count-and-delete action bar, the
/// leading selection circle, and the row wrapper that inserts the circle in
/// batch mode. Each catalog supplies its own l10n strings and accessibility
/// identifiers; the layout is one source of truth.

/// Bottom action bar for multi-select: a selected-count label, Clear, and a
/// destructive Delete that asks first, with a confirmation that points at its
/// button. The count string, delete label, confirmation copy, accessibility id,
/// and delete-enabled / busy flags vary per catalog; the layout is shared.
struct MobileBatchActionBar: View {
  let selectedCount: Int
  let countText: String
  let deleteLabel: String
  /// The question the delete confirmation asks.
  let confirmationTitle: String
  /// What a deletion means, under the question.
  let confirmationMessage: String?
  let canDelete: Bool
  let isBusy: Bool
  let accessibilityID: String
  let clear: () -> Void
  /// Deletes the selection once the confirmation is accepted.
  let delete: () -> Void

  @State private var isConfirmingDelete = false

  var body: some View {
    HStack(spacing: 12) {
      Text(countText)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(
        String(
          localized: "common.clear", defaultValue: "Clear", table: "Localizable",
          bundle: MobileL10n.bundle), action: clear
      )
      .disabled(selectedCount == 0 || isBusy)

      Button(role: .destructive) {
        isConfirmingDelete = true
      } label: {
        Label(deleteLabel, systemImage: "trash")
      }
      .disabled(!canDelete || isBusy)
      .mobileDeleteConfirmation(
        isPresented: $isConfirmingDelete,
        title: confirmationTitle,
        message: confirmationMessage,
        delete: delete
      )
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(.bar)
    .accessibilityIdentifier(accessibilityID)
  }
}

/// The leading multi-select indicator for a catalog row: a filled circle when
/// selected, hollow when not, tinting to the accent color on selection. The
/// accessibility label is supplied by the caller so each catalog can name its
/// own item.
struct MobileBatchSelectionIndicator: View {
  let isSelected: Bool
  let accessibilityLabel: String
  /// Grows with the body style the glyph is set in, so the glyph stays in its
  /// column at every text size.
  @ScaledMetric(relativeTo: .body) private var width: CGFloat = 22

  var body: some View {
    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
      .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      .frame(width: width)
      .accessibilityLabel(accessibilityLabel)
  }
}

/// A catalog row that grows a leading selection indicator in batch mode and
/// renders its content unchanged otherwise. Used by the Lists and Memory
/// catalogs, whose rows share this `HStack` shape.
struct MobileBatchSelectableRow<Content: View>: View {
  let isBatchSelecting: Bool
  let isSelected: Bool
  let selectionLabel: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 12) {
      if isBatchSelecting {
        MobileBatchSelectionIndicator(isSelected: isSelected, accessibilityLabel: selectionLabel)
      }
      content
    }
  }
}
