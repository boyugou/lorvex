import Foundation
import LorvexCore

/// Write surface for the synced `timezone` preference: the IANA zone every
/// device counts Lorvex's days in. The core re-anchors active reminders to
/// the new zone in the same write, so a reminder set for 9 AM stays at 9 AM
/// there.
extension MobileStore {
  /// Sets the product time zone, then refreshes so the Today snapshot, which
  /// carries the zone, and every day-scoped surface read in it. Returns false,
  /// with the error presented, when the core rejects the zone.
  @discardableResult
  func setLogicalTimeZone(_ identifier: String) async -> Bool {
    do {
      _ = try await core.setPreference(key: "timezone", value: identifier)
    } catch {
      await presentUserFacingError(error)
      return false
    }
    _ = await refresh()
    return true
  }
}
