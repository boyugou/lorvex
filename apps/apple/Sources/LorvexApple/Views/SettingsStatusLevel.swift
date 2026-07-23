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
    case .neutral: .secondary
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
  }
}
