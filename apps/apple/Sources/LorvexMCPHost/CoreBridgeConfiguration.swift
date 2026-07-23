import Foundation
import LorvexCore

/// Resolves which database the MCP host opens.
///
/// The shipping store is the single Lorvex-managed App Group database, opened by
/// leaving `databasePath` nil (the core's `DbLocator` resolves the managed
/// location). A launch-time `LORVEX_APPLE_DB_PATH` override is honored only on an
/// unsandboxed dev/source build. A sandboxed helper ignores any override entirely
/// and serves the managed store, so a stray inherited or hand-written
/// `LORVEX_APPLE_DB_PATH` can never split the helper onto a different database
/// than the app — silently resolving managed rather than failing, so an inherited
/// env var can't brick the helper.
struct CoreBridgeConfiguration {
  let databasePath: String?

  init(environment: [String: String], allowDefaultDatabase: Bool = true) throws {
    if let dbPath = environment["LORVEX_APPLE_DB_PATH"], !dbPath.isEmpty,
      !AppSandboxEnvironment.isSandboxed(environment: environment)
    {
      databasePath = dbPath
      return
    }

    guard allowDefaultDatabase else { throw MCPConfigurationError.databaseUnavailable }
    databasePath = nil
  }
}

enum MCPConfigurationError: LocalizedError {
  case databaseUnavailable

  var errorDescription: String? {
    switch self {
    case .databaseUnavailable:
      "No Lorvex database is configured for this MCP host."
    }
  }
}
