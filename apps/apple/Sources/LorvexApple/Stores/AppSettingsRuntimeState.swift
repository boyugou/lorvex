import Foundation
import LorvexCore

extension AppSettingsStore {
  /// Whether a launch-time `LORVEX_APPLE_DB_PATH` override is present. Used for
  /// unsandboxed dev/source builds only; read directly from the process
  /// environment, never persisted or dynamically switched.
  var usesEnvironmentDatabasePath: Bool {
    guard let explicitPath = environment["LORVEX_APPLE_DB_PATH"] else { return false }
    return !explicitPath.isEmpty
  }
}
