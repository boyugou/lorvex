import Foundation

/// The platform/surface the runtime is resolving for. Drives DB location and
/// capability decisions across the supported Apple platforms and non-Apple builds.
public enum RuntimePlatform: Sendable, Equatable {
  case macOS
  case iOS
  case visionOS
  case watchOS
  case otherUnix
  case windows

  /// The platform this binary was compiled for.
  public static var current: RuntimePlatform {
    #if os(macOS)
      return .macOS
    #elseif os(iOS)
      return .iOS
    #elseif os(visionOS)
      return .visionOS
    #elseif os(watchOS)
      return .watchOS
    #elseif os(Windows)
      return .windows
    #else
      return .otherUnix
    #endif
  }
}

/// Where the resolved DB path came from.
public enum DbPathSource: String, Sendable, Equatable {
  case envOverride = "env_override"
  case appleAppGroup = "apple_app_group"
  case platformDataDir = "platform_data_dir"
  case homeFallback = "home_fallback"
}

/// Structured diagnostic codes for rejected/ignored overrides.
public enum DbLocationDiagnosticCode: String, Sendable, Equatable {
  case dbPathOverrideIgnored = "db_path_override_ignored"
  case dbPathOverrideRejectedUnc = "db_path_override_rejected_unc"
}

/// One structured diagnostic captured during DB-path resolution.
public struct DbLocationDiagnostic: Sendable, Equatable {
  public let code: DbLocationDiagnosticCode
  public let message: String
  public let details: String?
  public let level: String

  static func warn(_ code: DbLocationDiagnosticCode, _ message: String, details: String? = nil)
    -> DbLocationDiagnostic
  {
    DbLocationDiagnostic(code: code, message: message, details: details, level: "warn")
  }
}

/// Full DB-path resolution result.
public struct DbLocationDetails: Sendable, Equatable {
  public let resolvedPath: String
  public let source: DbPathSource
  public let platformDefaultPath: String
  public let appleAppGroupPath: String?
  public let diagnostics: [DbLocationDiagnostic]
}

/// A hard resolution failure: no managed-storage location can be produced
/// without violating a storage-integrity invariant.
public enum DbLocationError: Error, Sendable, Equatable, CustomStringConvertible {
  /// A sandboxed Apple build (the App Group is its only managed-storage
  /// identity, so the ``DbLocatorEnvironment/allowsDbPathOverride`` dev override
  /// is off) could not resolve its App Group container:
  /// `containerURL(forSecurityApplicationGroupIdentifier:)` returned `nil`, or
  /// the container was otherwise inaccessible. Falling back to a per-process
  /// platform directory would put the app, the MCP helper, and each extension on
  /// *different* databases — a split store where every process silently "works"
  /// against its own data. Resolution fails closed instead. The associated value
  /// is the configured App Group identifier (when known) so the packaging /
  /// provisioning misconfiguration is diagnosable.
  case appGroupContainerUnavailable(appGroupIdentifier: String?)

  public var description: String {
    switch self {
    case .appGroupContainerUnavailable(let identifier):
      let named = identifier.map { "'\($0)'" } ?? "the configured App Group"
      return
        "App Group container for \(named) could not be resolved. This sandboxed build "
        + "requires its App Group entitlement to open the shared Lorvex database; without it "
        + "the app, MCP helper, and extensions would split across separate per-process stores. "
        + "Verify the App Group entitlement and provisioning profile."
    }
  }
}

/// Platform-I/O seam for the DB locator. The pure resolution pipeline
/// (precedence rules, UNC reject, default-path computation) takes these inputs;
/// the Apple app supplies a concrete impl backed by `FileManager` + the App
/// Group container (`NSFileManager.containerURLForSecurityApplicationGroupIdentifier`)
/// and the runtime sandbox check that decides `allowsDbPathOverride`.
public protocol DbLocatorEnvironment: Sendable {
  /// Raw `DB_PATH` env override, `nil` if unset. Honored only when
  /// ``allowsDbPathOverride`` is true; a build that forbids the override (a
  /// sandboxed Apple app or MCP helper) resolves managed storage even when this
  /// carries a value, and the resolver records a `dbPathOverrideIgnored`
  /// diagnostic.
  var dbPathEnvOverride: String? { get }
  /// Whether the ``dbPathEnvOverride`` may take effect for this build. `true` on
  /// unsandboxed dev/source builds (the only builds that honor the
  /// `LORVEX_APPLE_DB_PATH` dev override); `false` on sandboxed Apple planes,
  /// which always open the Lorvex-managed store. Defaults to `true` so
  /// non-Apple/test environments that model no sandbox keep honoring the
  /// override.
  var allowsDbPathOverride: Bool { get }
  /// Platform data directory (macOS/iOS `Application Support`, Linux
  /// `$XDG_DATA_HOME`/`~/.local/share`, Windows `%APPDATA%\Roaming`). `nil` if
  /// the platform could not resolve one.
  var dataDir: String? { get }
  /// User home directory, `nil` if unresolved.
  var homeDir: String? { get }
  /// The platform being resolved for.
  var platform: RuntimePlatform { get }
  /// App Group container path for Apple full apps/extensions. When available,
  /// this is the canonical managed-storage root for every Apple surface that
  /// shares local data. `nil` outside signed app/extension contexts, simulators
  /// without the entitlement, and tests that do not model App Groups.
  var appleAppGroupContainerPath: String? { get }
  /// The configured App Group identifier this build resolves managed storage
  /// against, independent of whether ``appleAppGroupContainerPath`` resolved.
  /// Used only to name the App Group in a fail-closed
  /// ``DbLocationError/appGroupContainerUnavailable(appGroupIdentifier:)`` so a
  /// packaging/provisioning misconfiguration is diagnosable; `nil` where no App
  /// Group applies (non-Apple builds, tests that model no App Group).
  var appleAppGroupIdentifier: String? { get }
}

public extension DbLocatorEnvironment {
  var appleAppGroupContainerPath: String? { nil }
  var appleAppGroupIdentifier: String? { nil }
  var allowsDbPathOverride: Bool { true }
}

/// In-memory ``DbLocatorEnvironment`` for tests: deterministic paths.
public struct InMemoryDbLocatorEnv: DbLocatorEnvironment {
  public var dbPathEnvOverride: String?
  public var dataDir: String?
  public var homeDir: String?
  public var platform: RuntimePlatform
  public var appleAppGroupContainerPath: String?
  public var allowsDbPathOverride: Bool
  public var appleAppGroupIdentifier: String?

  public init(
    dbPathEnvOverride: String? = nil, dataDir: String? = nil, homeDir: String? = nil,
    platform: RuntimePlatform = .otherUnix, appleAppGroupContainerPath: String? = nil,
    allowsDbPathOverride: Bool = true, appleAppGroupIdentifier: String? = nil
  ) {
    self.dbPathEnvOverride = dbPathEnvOverride
    self.dataDir = dataDir
    self.homeDir = homeDir
    self.platform = platform
    self.appleAppGroupContainerPath = appleAppGroupContainerPath
    self.allowsDbPathOverride = allowsDbPathOverride
    self.appleAppGroupIdentifier = appleAppGroupIdentifier
  }
}

/// Discovers where the SQLite DB lives, with explicit precedence and structured
/// diagnostics for any rejected/ignored override.
///
/// Precedence (first match wins):
///   1. `DB_PATH` env override (UNC rejected; ignored unless
///      ``DbLocatorEnvironment/allowsDbPathOverride`` is true — the dev override
///      is unsandboxed-only, so sandboxed Apple planes skip it)
///   2. Apple App Group container when available (shared by the app, widgets,
///      App Intents, CarPlay, and the macOS MCP helper)
///   3. Platform default (`<dataDir>/Lorvex/db.sqlite`)
///   4. Home fallback (`<home>/.local/share/Lorvex/db.sqlite`)
///
/// Fail-closed: a sandboxed build (``DbLocatorEnvironment/allowsDbPathOverride``
/// is `false`, so the App Group is its only managed-storage identity) whose App
/// Group container did not resolve throws
/// ``DbLocationError/appGroupContainerUnavailable(appGroupIdentifier:)`` instead
/// of dropping to steps 3/4. Those per-process directories differ across the
/// app, MCP helper, and extensions, so a silent fallback there would split the
/// store. The platform-default/home steps remain reachable only for unsandboxed
/// dev/source and non-Apple builds, which have no App Group and no split-store
/// risk.
public enum DbLocator {
  static let lorvexDir = "Lorvex"
  static let dbFile = "db.sqlite"

  /// Resolve full details from `env`. Throws
  /// ``DbLocationError/appGroupContainerUnavailable(appGroupIdentifier:)`` when a
  /// sandboxed build's App Group container is unresolvable (see the type's
  /// precedence note).
  public static func resolveDetails(_ env: any DbLocatorEnvironment) throws -> DbLocationDetails {
    var diagnostics: [DbLocationDiagnostic] = []

    let platformDefaultPath: String = {
      if let dataDir = env.dataDir {
        return join(dataDir, lorvexDir, dbFile)
      }
      let base = env.homeDir ?? "."
      return join(base, ".local", "share", lorvexDir, dbFile)
    }()

    let appleAppGroupPath = env.appleAppGroupContainerPath.map {
      join($0, lorvexDir, dbFile)
    }

    // 1. Env override.
    if let raw = env.dbPathEnvOverride?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
      if !env.allowsDbPathOverride {
        diagnostics.append(
          .warn(
            .dbPathOverrideIgnored,
            "DB_PATH override ignored; using managed storage",
            details:
              "The LORVEX_APPLE_DB_PATH override is an unsandboxed dev/source-build feature; "
              + "this build resolves the Lorvex-managed store."
          ))
      } else if isWindowsUncPath(raw, platform: env.platform) {
        diagnostics.append(
          .warn(
            .dbPathOverrideRejectedUnc,
            "DB_PATH override rejected; using managed storage",
            details:
              "UNC / network share paths are not supported because SQLite WAL mode is unsafe over SMB."
          ))
      } else {
        return DbLocationDetails(
          resolvedPath: raw, source: .envOverride, platformDefaultPath: platformDefaultPath,
          appleAppGroupPath: appleAppGroupPath, diagnostics: diagnostics)
      }
    }

    // Fail closed for a sandboxed build whose App Group container did not
    // resolve. There, the App Group is the only shared managed-storage identity
    // (the dev override is off), so dropping to the per-process platform/home
    // directory below would split the store across the app, MCP helper, and
    // extensions. Refuse instead, naming the App Group so the packaging /
    // provisioning fault is diagnosable.
    if !env.allowsDbPathOverride, appleAppGroupPath == nil {
      throw DbLocationError.appGroupContainerUnavailable(
        appGroupIdentifier: env.appleAppGroupIdentifier)
    }

    // 2. Apple App Group container. This is the canonical default for signed
    // Apple app/extension/helper surfaces because each process sees a different
    // sandbox container but the same App Group container.
    if let appleAppGroupPath {
      return DbLocationDetails(
        resolvedPath: appleAppGroupPath, source: .appleAppGroup,
        platformDefaultPath: platformDefaultPath, appleAppGroupPath: appleAppGroupPath,
        diagnostics: diagnostics)
    }

    // 3 / 4. Platform default vs. home fallback.
    let source: DbPathSource = env.dataDir != nil ? .platformDataDir : .homeFallback
    return DbLocationDetails(
      resolvedPath: platformDefaultPath, source: source,
      platformDefaultPath: platformDefaultPath, appleAppGroupPath: appleAppGroupPath,
      diagnostics: diagnostics)
  }

  /// Resolve just the path (diagnostics discarded). Throws the same fail-closed
  /// ``DbLocationError`` as ``resolveDetails(_:)``.
  public static func resolvePath(_ env: any DbLocatorEnvironment) throws -> String {
    try resolveDetails(env).resolvedPath
  }

  /// Detect Windows UNC / network share paths. The backslash arm
  /// (`\\server\share`) is rejected on every platform; the forward-slash arm
  /// (`//server/share`) is UNC only on Windows (on Unix `//Volumes/Data` is a
  /// valid POSIX path).
  static func isWindowsUncPath(_ path: String, platform: RuntimePlatform) -> Bool {
    guard path.count >= 2 else { return false }
    if path.hasPrefix("\\\\") { return true }
    if platform == .windows && path.hasPrefix("//") { return true }
    return false
  }

  private static func join(_ components: String...) -> String {
    var url = URL(fileURLWithPath: components[0], isDirectory: true)
    for component in components.dropFirst() {
      url.appendPathComponent(component)
    }
    return url.path
  }
}
