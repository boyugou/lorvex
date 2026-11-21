import LorvexCore
import SwiftUI

/// Shared layout for confirmations above the tab bar.
private struct MobileActionBanner: View {
  let message: String
  var detail: String? = nil
  let buttonTitle: String
  let identifier: String
  let action: () -> Void
  var isCaptureReceipt = false
  @AccessibilityFocusState(for: .voiceOver) private var messageFocused: Bool
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
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
          actionButton.padding(.leading, -LorvexDesign.Spacing.m)
        }
      } else {
        HStack(spacing: LorvexDesign.Spacing.l) {
          messageText
          Spacer(minLength: LorvexDesign.Spacing.m)
          actionButton
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
    .accessibilityIdentifier(identifier + ".banner")
  }

  private var messageText: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Text(verbatim: message)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(.primary)
        .lineLimit(isCaptureReceipt || !dynamicTypeSize.isAccessibilitySize ? 2 : nil)
      if let detail {
        Text(verbatim: detail)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .lineLimit(isCaptureReceipt || !dynamicTypeSize.isAccessibilitySize ? 2 : nil)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityFocused($messageFocused)
    .task(id: voiceOverEnabled) {
      // Dismissing the sheet returns the system focus to Today or its tab bar.
      // Put the receipt and its following Open button into the reading order.
      guard isCaptureReceipt, voiceOverEnabled else { return }
      await Task.yield()
      guard !Task.isCancelled else { return }
      messageFocused = true
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var actionButton: some View {
    Button(action: action) {
      Text(verbatim: buttonTitle)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier + ".button")
  }
}

/// Keeps both actions reachable when a capture follows an undoable change.
private struct MobileActionBannerOverlay: ViewModifier {
  let receipt: MobileCaptureReceipt?
  let open: (MobileCaptureReceipt) -> Void
  let dismissReceipt: (MobileCaptureReceipt) -> Void
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

  private var bannerTransition: AnyTransition {
    reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
  }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        VStack(spacing: LorvexDesign.Spacing.s) {
          if let offer {
            MobileActionBanner(message: offer.message, buttonTitle: MobileUndoCopy.undo, identifier: "mobile.undo", action: undo)
              .transition(bannerTransition)
              .task(id: offer.id) {
                AccessibilityNotification.Announcement(offer.message).post()
                guard (try? await Task.sleep(for: .seconds(voiceOverEnabled ? 12 : 6))) != nil else { return }
                dismiss()
              }
          }
          if let receipt {
            MobileActionBanner(
              message: receipt.title, detail: receipt.detail, buttonTitle: MobileCaptureReceipt.open,
              identifier: "capture.receipt", action: { open(receipt) }, isCaptureReceipt: true)
              .transition(bannerTransition)
              .accessibilityAction(.escape) { dismissReceipt(receipt) }
              .id(receipt.id)
              .task(id: voiceOverEnabled) {
                // Keep Open reachable while someone explores the screen with VoiceOver.
                guard !voiceOverEnabled,
                  (try? await Task.sleep(for: .seconds(8))) != nil else { return }
                dismissReceipt(receipt)
              }
          }
        }
        .padding(.horizontal)
        .padding(.bottom, bottomPadding)
      }
  }
}

extension View {
  func lorvexMobileActionBanners(
    receipt: MobileCaptureReceipt?, open: @escaping (MobileCaptureReceipt) -> Void,
    dismissReceipt: @escaping (MobileCaptureReceipt) -> Void, undoOffer: MobileUndoOffer?,
    undo: @escaping () -> Void, dismissUndo: @escaping () -> Void
  ) -> some View {
    modifier(MobileActionBannerOverlay(
      receipt: receipt, open: open, dismissReceipt: dismissReceipt, offer: undoOffer, undo: undo, dismiss: dismissUndo))
  }
}
