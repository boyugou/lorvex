import LorvexCore
import SwiftUI

/// The shared "collapse this detail panel" control — a consistent ✕ in the
/// top-trailing corner of every right-hand inspector (task, habit, calendar
/// event), so the panel always closes the same way across surfaces. It pairs
/// with re-clicking the open list item, which toggles the same selection.
struct InspectorCloseButton: View {
  /// Per-surface identifier so existing UI hooks keep working.
  var accessibilityIdentifier: String
  let action: () -> Void

  var body: some View {
    LorvexIconButton(
      systemImage: "xmark",
      label: String(localized: "common.close", defaultValue: "Close", table: "Localizable", bundle: LorvexL10n.bundle),
      accessibilityIdentifier: accessibilityIdentifier,
      action: action)
  }
}
