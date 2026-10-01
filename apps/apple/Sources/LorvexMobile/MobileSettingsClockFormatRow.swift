import LorvexCore
import LorvexWidgetKitSupport
import SwiftUI

/// The Clock picker in Settings: follow the system's 12/24-hour setting, or
/// always show a 12-hour or 24-hour clock. Each choice shows a sample time in
/// its own clock ("12-Hour (9:41 PM)"), so the menu says what it changes
/// without a footer. A change applies at once to the app, which reads the
/// choice through `lorvexClockLocale()`, and reloads the widgets, which format
/// their times when they draw.
struct MobileSettingsClockFormatRow: View {
  @AppStorage(LorvexClockFormat.preferenceKey, store: LorvexClockFormat.defaults)
  private var format: LorvexClockFormat = .system

  var body: some View {
    Picker(
      String(
        localized: "settings.clock", defaultValue: "Clock", table: "Localizable",
        bundle: MobileL10n.bundle),
      selection: $format
    ) {
      ForEach(LorvexClockFormat.allCases) { choice in
        Text(label(choice)).tag(choice)
      }
    }
    // Pushes its choices like the Language row above it, so the group's rows
    // read alike. The style is iOS-only; the module also compiles for macOS.
    #if os(iOS)
      .pickerStyle(.navigationLink)
    #endif
    .onChange(of: format) { _, _ in GlanceSurfaceReloader.live.reloadAll() }
    .accessibilityIdentifier("mobileSettings.clock")
  }

  private func label(_ choice: LorvexClockFormat) -> String {
    let sample = LorvexDateFormatters.clockTime(
      Self.sampleTime, locale: choice.applied(to: .current))
    switch choice {
    case .system:
      return String(
        localized: "settings.clock.system", defaultValue: "System (\(sample))",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .twelveHour:
      return String(
        localized: "settings.clock.twelve_hour", defaultValue: "12-Hour (\(sample))",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .twentyFourHour:
      return String(
        localized: "settings.clock.twenty_four_hour", defaultValue: "24-Hour (\(sample))",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  /// 9:41 PM today: an afternoon time, so a 24-hour sample ("21:41") reads
  /// differently from a 12-hour one.
  private static var sampleTime: Date {
    Calendar.current.date(bySettingHour: 21, minute: 41, second: 0, of: Date()) ?? Date()
  }
}
