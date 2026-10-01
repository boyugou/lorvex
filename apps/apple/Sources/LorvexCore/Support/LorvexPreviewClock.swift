import Foundation

/// The product-day clock a DEBUG preview run pins with the launch argument
/// `-lorvexPreviewNow HH:mm`, so a headless capture shows the same Today
/// whatever the hour it runs at. `pinnedMinutes` is minutes since midnight,
/// or `nil` in release builds and when the argument is absent or malformed;
/// the stores fall back to the real clock then.
public enum LorvexPreviewClock {
  public static let pinnedMinutes: Int? = {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-lorvexPreviewNow"), index + 1 < arguments.count
      else { return nil }
      return lorvexMinutesSinceMidnight(arguments[index + 1])
    #else
      return nil
    #endif
  }()

  /// The moment a product-day surface draws its clock at: `tick` (the real
  /// time, or a timeline's current date), or `tick`'s day at `pinnedMinutes`
  /// in `calendar` when a preview run pins it, so a day grid's now line and
  /// its opening scroll position match the Today the same capture shows.
  public static func now(in calendar: Calendar, tick: Date = Date()) -> Date {
    guard let pinnedMinutes else { return tick }
    let start = calendar.startOfDay(for: tick)
    return calendar.date(byAdding: .minute, value: pinnedMinutes, to: start) ?? tick
  }
}
