import LorvexCore
import SwiftUI

/// A navigation/settings list row in the refined-native vocabulary: a colored
/// icon tile, a title (with optional subtitle), and an optional trailing value.
/// This is the mature-app idiom (think Settings rows) — the leading tile is what
/// makes hub lists read as designed rather than a stock pile of `Label`s.
struct MobileNavigationRow: View {
  let title: String
  let systemImage: String
  var tint: Color = LorvexDesign.Palette.accent
  var subtitle: String? = nil
  var value: String? = nil

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
            .lineLimit(1)
        }
      }
      if let value {
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text(value)
          .font(.body)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(value == nil ? title : "\(title), \(value ?? "")")
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
