import LorvexCore
import SwiftUI

/// Status severity for a Settings status/overview row, shared across the
/// diagnostics, calendar, and CloudSync sections so the color ramp is defined
/// in one place. `.error` is available to every section; the CloudSync overview
/// simply never produces it.
enum SettingsStatusLevel {
  case neutral
  case success
  case warning
  case error

  var color: Color {
    switch self {
    case .neutral: LorvexDesign.Palette.neutral
    case .success: LorvexDesign.Palette.success
    case .warning: LorvexDesign.Palette.warning
    case .error: LorvexDesign.Palette.error
    }
  }
}
