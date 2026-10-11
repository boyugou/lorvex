import LorvexCore
import SwiftUI

/// The banner that follows a change which can be taken back (completing,
/// cancelling, or filing tasks into another list): what happened, and an Undo
/// button, on floating material. At accessibility text sizes the button moves
/// under the message, so a translated word keeps its line.
struct MobileUndoBanner: View {
  let message: String
  let undo: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The widest the banner grows, so on an iPad it stays a compact card
  /// instead of spanning the screen.
  private static let maxWidth: CGFloat = 520

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          messageText
          // The button's own side padding is its tap area; pull it back so
          // the word lines up with the message above.
          undoButton.padding(.leading, -LorvexDesign.Spacing.m)
        }
      } else {
        HStack(spacing: LorvexDesign.Spacing.l) {
          messageText
          Spacer(minLength: LorvexDesign.Spacing.m)
          undoButton
        }
      }
    }
    .padding(.leading, LorvexDesign.Spacing.l)
    .padding(.trailing, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .frame(maxWidth: Self.maxWidth)
    .background(.regularMaterial, in: shape)
    .overlay { shape.stroke(Color.primary.opacity(0.08), lineWidth: 1) }
    .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mobile.undo.banner")
  }

  private var messageText: some View {
    Text(verbatim: message)
      .font(LorvexDesign.Typography.primaryText)
      .foregroundStyle(.primary)
      .lineLimitUnlessAccessibilitySize(2)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var undoButton: some View {
    Button(action: undo) {
      Text(verbatim: MobileUndoCopy.undo)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("mobile.undo.button")
  }
}

/// Floats the Undo banner above the bottom of the screen while a change is on
/// offer: clear of the tab bar on an iPhone, where it floats above the bottom
/// edge, and near the edge on an iPad, where the tab bar is on top. The
/// banner is announced to VoiceOver as it appears and goes away by itself
/// after a few seconds, longer while VoiceOver is on.
private struct MobileUndoBannerOverlay: ViewModifier {
  let offer: MobileUndoOffer?
  let undo: () -> Void
  let dismiss: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// The height the iPhone tab bar occupies above the bottom edge. The bar
  /// keeps one height at every text size, so this does not scale with Dynamic
  /// Type: a scaled value floats the banner in the middle of the screen at
  /// accessibility sizes.
  private static let tabBarClearance: CGFloat = 84

  private var bottomPadding: CGFloat {
    horizontalSizeClass == .compact ? Self.tabBarClearance : LorvexDesign.Spacing.l
  }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let offer {
          MobileUndoBanner(message: offer.message, undo: undo)
            .padding(.horizontal)
            .padding(.bottom, bottomPadding)
            .transition(
              reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .task(id: offer.id) {
              AccessibilityNotification.Announcement(offer.message).post()
              // Only a genuine timeout dismisses: a cancelled sleep means a
              // newer change replaced this one, and its own timer takes over.
              guard (try? await Task.sleep(for: .seconds(voiceOverEnabled ? 12 : 6))) != nil
              else { return }
              dismiss()
            }
        }
      }
  }
}

extension View {
  /// Floats the Undo banner for `offer` over this view (``MobileUndoBannerOverlay``).
  func lorvexMobileUndoBanner(
    _ offer: MobileUndoOffer?, undo: @escaping () -> Void, dismiss: @escaping () -> Void
  ) -> some View {
    modifier(MobileUndoBannerOverlay(offer: offer, undo: undo, dismiss: dismiss))
  }
}
