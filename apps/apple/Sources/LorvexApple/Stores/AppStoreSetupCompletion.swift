import Foundation
import LorvexCore

/// Mirrors a finished macOS onboarding into the core's setup state. The
/// wizard's own flag lives in app-side defaults and only gates the sheet;
/// assistants read the core's `setup_completed` / readiness via
/// `get_setup_status` — without this write they would keep steering a fully
/// onboarded user through getting-started guidance.
extension AppStore {
  func markCoreSetupComplete() async {
    // Seed the engine's default working hours only when none are stored —
    // never overwrite a window the user or assistant already chose.
    var workingHours: String?
    // `getPreference` returns `String?`; `try?` wraps that in a second optional,
    // so flatten both layers — a stored value at either layer means "leave it".
    let existing = (try? await core.getPreference(key: "working_hours")) ?? nil
    if existing == nil {
      workingHours = #"{"start":"09:00","end":"18:00"}"#
    }
    do {
      _ = try await core.completeSetup(
        workingHours: workingHours,
        defaultListID: nil,
        timezone: TimeZone.current.identifier)
      errorMessage = nil
    } catch {
      // Onboarding itself is done; surface the sync failure without undoing it.
      await presentUserFacingError(error)
    }
  }
}
