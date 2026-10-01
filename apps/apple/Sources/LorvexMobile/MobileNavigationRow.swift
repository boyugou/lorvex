import LorvexCore
import SwiftUI

/// A navigation/settings list row in the refined-native vocabulary: a colored
/// icon tile, a title (with optional subtitle), and an optional trailing count.
/// This is the mature-app idiom (think Settings rows) — the leading tile is what
/// makes hub lists read as designed rather than a stock pile of `Label`s, and it
/// is what keeps a row's automatic separator inset aligned with the tiled rows
/// around it.
///
/// `count` renders in the same face as ``MobileListCatalogRow``'s count, so a
/// section that mixes the two reads as one right-aligned column of numbers,
/// and like it draws nothing at zero: an empty destination needs no number.
struct MobileNavigationRow: View {
  let title: String
  let systemImage: String
  var tint: Color = LorvexDesign.Palette.accent
  var subtitle: String? = nil
  var count: Int? = nil

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: systemImage, tint: tint, size: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.body)
          .foregroundStyle(.primary)
        if let subtitle {
          Text(subtitle)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      if let count, count > 0 {
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text("\(count)")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  /// VoiceOver reads title, then subtitle, then trailing count — the same
  /// top-to-bottom, leading-to-trailing order the row draws. Omitting `subtitle`
  /// (as a plain `title[, count]` label would) drops a row's only descriptive
  /// text — e.g. a settings hub row whose subtitle is its current selection.
  private var accessibilityLabel: String {
    [title, subtitle, count.flatMap { $0 > 0 ? String($0) : nil }].compactMap { $0 }
      .joined(separator: ", ")
  }
}

extension MobileDestination {
  /// A distinct tile tint per destination — the colorful, glanceable iconography
  /// of a well-made hub list.
  var tileTint: Color {
    switch self {
    case .tasks: .blue
    case .calendar: .red
    case .habits: .green
    case .lists: .orange
    case .memory: .purple
    case .review: .indigo
    case .settings: .gray
    }
  }
}
