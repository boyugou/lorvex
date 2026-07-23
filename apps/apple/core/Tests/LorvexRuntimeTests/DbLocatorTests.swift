import XCTest

@testable import LorvexRuntime

/// Ports the pipeline-shape cases of `lorvex-runtime/src/db_locator/tests.rs`
/// (env override precedence, blank-ignore, UNC reject, platform default, macOS
/// default fallback) and covers the sandboxed fail-closed rule. The `DB_PATH`
/// sandbox gate (`allowsDbPathOverride`) and the real App Group container lookup
/// are platform I/O (the sandbox evaluation and
/// `containerURLForSecurityApplicationGroupIdentifier` resolution live in the
/// concrete `DbLocatorEnvironment` impl supplied by the app), so those parts are
/// modeled here with explicit env values rather than touching OS containers.
final class DbLocatorTests: XCTestCase {
  func testDbPathEnvOverrideWins() throws {
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: " /tmp/lorvex-dev.sqlite ", dataDir: "/ignored", homeDir: "/also-ignored")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/tmp/lorvex-dev.sqlite")
    XCTAssertEqual(details.source, .envOverride)
  }

  func testBlankEnvIsIgnored() throws {
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: "   ", dataDir: "/data", homeDir: "/home/tester")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/data/Lorvex/db.sqlite")
    XCTAssertEqual(details.source, .platformDataDir)
  }

  func testDbPathOverrideIgnoredWhenNotAllowedFallsBackToAppGroup() throws {
    // A sandboxed Apple plane sets allowsDbPathOverride: false; the resolver
    // drops the override and opens the App Group container instead, recording a
    // dbPathOverrideIgnored diagnostic.
    let appGroup = "/Users/tester/Library/Group Containers/group.com.lorvex.apple"
    let expected = "\(appGroup)/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: "/tmp/dev-override.sqlite",
      dataDir: "/Users/tester/Library/Application Support",
      homeDir: "/Users/tester",
      platform: .macOS,
      appleAppGroupContainerPath: appGroup,
      allowsDbPathOverride: false)
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, expected)
    XCTAssertEqual(details.source, .appleAppGroup)
    XCTAssertEqual(details.diagnostics.count, 1)
    XCTAssertEqual(details.diagnostics[0].code, .dbPathOverrideIgnored)
  }

  func testAppleAppGroupBeatsPlatformDataDir() throws {
    let appGroup = "/Users/tester/Library/Group Containers/group.com.lorvex.apple"
    let expected = "\(appGroup)/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(
      dataDir: "/Users/tester/Library/Application Support",
      homeDir: "/Users/tester",
      platform: .macOS,
      appleAppGroupContainerPath: appGroup)
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, expected)
    XCTAssertEqual(details.source, .appleAppGroup)
    XCTAssertEqual(details.appleAppGroupPath, expected)
  }

  /// Sandboxed (dev override off) + App Group container resolvable → the shared
  /// container is used; no fail-closed. This is the healthy sandboxed-production
  /// path.
  func testSandboxedResolvesAppGroupContainer() throws {
    let appGroup = "/private/var/mobile/Containers/Shared/AppGroup/ABC"
    let expected = "\(appGroup)/Lorvex/db.sqlite"
    let env = InMemoryDbLocatorEnv(
      dataDir: "/private/var/mobile/Containers/Data/Application/XYZ/Library/Application Support",
      homeDir: "/private/var/mobile",
      platform: .iOS,
      appleAppGroupContainerPath: appGroup,
      allowsDbPathOverride: false,
      appleAppGroupIdentifier: "group.com.lorvex.apple")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, expected)
    XCTAssertEqual(details.source, .appleAppGroup)
  }

  /// Sandboxed (dev override off) + App Group container unresolvable → fail
  /// closed. The resolver throws instead of returning a per-process platform /
  /// home path, which would split the store across the app, MCP helper, and
  /// extensions. The error names the missing App Group.
  func testSandboxedWithoutAppGroupFailsClosed() throws {
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: "/tmp/dev-override.sqlite",
      dataDir: "/private/var/mobile/Containers/Data/Application/XYZ/Library/Application Support",
      homeDir: "/private/var/mobile",
      platform: .iOS,
      appleAppGroupContainerPath: nil,
      allowsDbPathOverride: false,
      appleAppGroupIdentifier: "group.com.lorvex.apple")
    XCTAssertThrowsError(try DbLocator.resolveDetails(env)) { error in
      XCTAssertEqual(
        error as? DbLocationError,
        .appGroupContainerUnavailable(appGroupIdentifier: "group.com.lorvex.apple"))
      // The error text names the App Group so the misconfiguration is diagnosable.
      XCTAssertTrue(
        "\(error)".contains("group.com.lorvex.apple"),
        "fail-closed error must name the missing App Group; got \(error)")
    }
  }

  /// Unsandboxed dev/source build (dev override on) with no App Group modeled
  /// still resolves the platform default — the fail-closed rule is gated to
  /// sandboxed builds, so local development is unaffected.
  func testUnsandboxedWithoutAppGroupFallsBackToPlatformDefault() throws {
    let env = InMemoryDbLocatorEnv(
      dataDir: "/Users/dev/Library/Application Support",
      homeDir: "/Users/dev",
      platform: .macOS,
      appleAppGroupContainerPath: nil,
      allowsDbPathOverride: true)
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/Users/dev/Library/Application Support/Lorvex/db.sqlite")
    XCTAssertEqual(details.source, .platformDataDir)
  }

  func testUncDbPathOverrideRejectedAndFallsBackToPlatformDefault() throws {
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: "\\\\fileserver\\share\\db.sqlite", dataDir: "/data",
      homeDir: "/Users/tester")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/data/Lorvex/db.sqlite")
    XCTAssertEqual(details.source, .platformDataDir)
    XCTAssertEqual(details.diagnostics.count, 1)
    XCTAssertEqual(details.diagnostics[0].code, .dbPathOverrideRejectedUnc)
    XCTAssertTrue(details.diagnostics[0].details?.contains("UNC / network share paths") ?? false)
    XCTAssertFalse(details.diagnostics[0].details?.contains("fileserver") ?? true)
  }

  func testIsWindowsUncPathClassifiesBothForms() {
    XCTAssertTrue(DbLocator.isWindowsUncPath("\\\\server\\share", platform: .windows))
    XCTAssertTrue(DbLocator.isWindowsUncPath("\\\\server\\share", platform: .macOS))
    // Forward-slash `//` is UNC only on Windows.
    XCTAssertTrue(DbLocator.isWindowsUncPath("//server/share", platform: .windows))
    XCTAssertFalse(DbLocator.isWindowsUncPath("//server/share", platform: .macOS))
    XCTAssertFalse(DbLocator.isWindowsUncPath("C:\\Users\\me\\db.sqlite", platform: .windows))
    XCTAssertFalse(DbLocator.isWindowsUncPath("/home/me/db.sqlite", platform: .macOS))
    XCTAssertFalse(DbLocator.isWindowsUncPath("", platform: .windows))
    XCTAssertFalse(DbLocator.isWindowsUncPath("\\", platform: .windows))
  }

  func testForwardSlashPathIsNotTreatedAsUncOnUnix() throws {
    let env = InMemoryDbLocatorEnv(
      dbPathEnvOverride: "//Volumes/Data/db.sqlite", dataDir: "/data", homeDir: "/Users/tester",
      platform: .otherUnix)
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "//Volumes/Data/db.sqlite")
    XCTAssertEqual(details.source, .envOverride)
  }

  func testFallsBackToPlatformDataDir() throws {
    let env = InMemoryDbLocatorEnv(dataDir: "/var/data", homeDir: "/Users/tester")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/var/data/Lorvex/db.sqlite")
    XCTAssertEqual(details.platformDefaultPath, "/var/data/Lorvex/db.sqlite")
  }

  func testFallsBackToHomeWhenNoDataDir() throws {
    let env = InMemoryDbLocatorEnv(dataDir: nil, homeDir: "/home/tester")
    let details = try DbLocator.resolveDetails(env)
    XCTAssertEqual(details.resolvedPath, "/home/tester/.local/share/Lorvex/db.sqlite")
    XCTAssertEqual(details.source, .homeFallback)
  }
}
