import LorvexCore
import SwiftUI

@MainActor
func stepHeader(icon: String, title: String, subtitle: String) -> some View {
  VStack(alignment: .leading, spacing: 6) {
    Label(title, systemImage: icon)
      .font(LorvexDesign.Typography.sectionHeader)
    Text(subtitle)
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
  }
}

@MainActor
func nextButton(action: @escaping () -> Void, label: String? = nil) -> some View {
  HStack {
    Spacer()
    Button(label ?? String(localized: "setup.action.next", defaultValue: "Next", table: "Localizable", bundle: LorvexL10n.bundle), action: action)
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
  }
}
