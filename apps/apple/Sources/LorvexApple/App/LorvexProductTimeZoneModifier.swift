import LorvexCore
import SwiftUI

/// Puts the store's product time zone in the environment
/// (`lorvexProductTimeZone`) and keeps it current when the synced setting
/// changes, so the task rows below count their due days in it.
private struct LorvexProductTimeZoneModifier: ViewModifier {
  let store: AppStore

  func body(content: Content) -> some View {
    content.environment(\.lorvexProductTimeZone, store.logicalTimeZone)
  }
}

extension View {
  /// Sets `lorvexProductTimeZone` from `store`. Apply it once at each scene
  /// root, beside `lorvexClockLocale()`.
  func lorvexProductTimeZone(from store: AppStore) -> some View {
    modifier(LorvexProductTimeZoneModifier(store: store))
  }
}
