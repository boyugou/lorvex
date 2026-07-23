import Foundation
import LorvexCore

/// Presents stored HH:mm clock strings using the user's 12-/24-hour preference.
/// Thin alias over the shared ``lorvexClockTimeLabel(_:)`` so every surface
/// (macOS + mobile) formats clock times identically.
func mobileClockTimeLabel(_ hourMinute: String) -> String {
  lorvexClockTimeLabel(hourMinute)
}
