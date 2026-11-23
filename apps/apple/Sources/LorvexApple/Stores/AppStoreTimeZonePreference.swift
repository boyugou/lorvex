import Foundation
import LorvexCore

/// Write surface for the synced `timezone` preference: the IANA zone every
/// device counts Lorvex's days in. The core re-anchors active reminders to
/// the new zone in the same write, so a reminder set for 9 AM stays at 9 AM
/// there.
extension AppStore {
  /// Sets the product time zone, then refreshes so the Today snapshot, which
  /// carries the zone, and every day-scoped surface read in it. Reports success
  /// only once the refreshed snapshot shows the requested zone, under the
  /// identifier the preference stores for it; read and write
  /// failures are presented through the store's error surface.
  @discardableResult
  func setLogicalTimeZone(_ identifier: String) async -> Bool {
    do {
      _ = try await core.setPreference(key: "timezone", value: identifier)
    } catch {
      await presentUserFacingError(error)
      return false
    }
    await refreshAndWaitForLatest()
    return today.timezone == LorvexTimeZoneChoice.storedIdentifier(for: identifier)
  }
}
