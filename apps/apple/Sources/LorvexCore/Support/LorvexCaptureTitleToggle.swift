import SwiftUI

/// Offers a per-draft choice when words in a task title look like scheduling
/// details. The choice exposes its selected state to VoiceOver.
public struct LorvexCaptureTitleToggle: View {
  @Binding private var keepsOriginalTitle: Bool

  public init(keepsOriginalTitle: Binding<Bool>) {
    _keepsOriginalTitle = keepsOriginalTitle
  }

  public nonisolated static var title: String {
    String(
      localized: "capture.keep_original_title", defaultValue: "Keep title as typed",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  public var body: some View {
    #if os(iOS)
      Button {
        keepsOriginalTitle.toggle()
      } label: {
        HStack {
          Text(Self.title)
          Spacer(minLength: LorvexDesign.Spacing.s)
          Image(systemName: keepsOriginalTitle ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(keepsOriginalTitle ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(keepsOriginalTitle ? .isSelected : [])
      .accessibilityIdentifier("capture.keepOriginalTitle")
    #else
      Toggle(Self.title, isOn: $keepsOriginalTitle)
        .font(LorvexDesign.Typography.secondaryText)
        .accessibilityIdentifier("capture.keepOriginalTitle")
    #endif
  }
}
