import LorvexCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

struct MobileSettingsRecoveryLink: View {
  let label: String
  let accessibilityIdentifier: String

  var body: some View {
    if let settingsURL = Self.settingsURL {
      Link(label, destination: settingsURL)
        .font(LorvexDesign.Typography.tertiaryText)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
  }

  private static var settingsURL: URL? {
    #if canImport(UIKit)
      URL(string: UIApplication.openSettingsURLString)
    #else
      nil
    #endif
  }
}
