import SwiftUI

/// The one tinted capsule for status pills, count badges, and signal chips.
///
/// A chip is `tertiaryText` at medium weight on a 12% tint fill, with the tint
/// as foreground, so every pill across macOS, iOS, watchOS, and widgets shares
/// one size and one color treatment. Pass a `LorvexDesign.Palette` token as the
/// tint: a status chip carries its status color, a count chip stays `neutral`.
public struct LorvexChip: View {
  private let text: String
  private let systemImage: String?
  private let tint: Color

  public init(_ text: String, systemImage: String? = nil, tint: Color = LorvexDesign.Palette.neutral) {
    self.text = text
    self.systemImage = systemImage
    self.tint = tint
  }

  public var body: some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      if let systemImage {
        Image(systemName: systemImage)
          .imageScale(.small)
          .accessibilityHidden(true)
      }
      Text(text)
        .lineLimit(1)
    }
    .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, Self.horizontalPadding)
    .padding(.vertical, Self.verticalPadding)
    .background(tint.opacity(0.12), in: Capsule())
  }

  private static var horizontalPadding: CGFloat {
    #if os(macOS)
      LorvexDesign.Spacing.sm
    #else
      LorvexDesign.Spacing.s
    #endif
  }

  private static var verticalPadding: CGFloat {
    #if os(macOS)
      LorvexDesign.Spacing.xxs
    #else
      LorvexDesign.Spacing.xs
    #endif
  }
}
