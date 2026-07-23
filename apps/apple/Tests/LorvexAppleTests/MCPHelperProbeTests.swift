import Foundation
import Testing

@testable import LorvexApple

private func makeSyntheticBundle() throws -> URL {
  let base = FileManager.default.temporaryDirectory
    .appendingPathComponent("mcp-probe-\(UUID().uuidString)", isDirectory: true)
  // Mirrors the packaged shape: the helper ships as a bundled app
  // (Contents/Helpers/<host>.app/Contents/MacOS/<host>), not a bare Mach-O.
  try FileManager.default.createDirectory(
    at: base.appendingPathComponent("Contents/Helpers/LorvexMCPHost.app/Contents/MacOS"),
    withIntermediateDirectories: true
  )
  return base
}

@Test
func mcpHelperProbeReportsReadyWhenHelperPresentAndExecutable() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

  #expect(await MCPHelperProbe.probe(bundleURL: bundle) == .ready)
}

@Test
func mcpHelperProbeReportsRuntimeFailureWhenSelfCheckFails() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  try Data("#!/bin/sh\nexit 42\n".utf8).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

  #expect(await MCPHelperProbe.probe(bundleURL: bundle) == .runtimeFailed)
}

@Test
func mcpHelperProbeReportsMissingWhenHelperAbsent() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  #expect(await MCPHelperProbe.probe(bundleURL: bundle) == .helperMissing)
}

@Test
func mcpHelperProbeReportsNotExecutableWhenExecutableBitCleared() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  try Data("placeholder".utf8).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helper.path)

  #expect(await MCPHelperProbe.probe(bundleURL: bundle) == .helperNotExecutable)
}

/// Regression coverage for a hung helper: before the fix, the probe's task
/// group awaited a `Process.terminationHandler` continuation nothing could
/// cancel, so a helper that never exits blocked the probe forever instead of
/// timing out. The fake helper here ignores SIGTERM too, so the probe only
/// succeeds if its SIGKILL escalation actually runs.
@Test
func mcpHelperProbeTimesOutAndKillsAHungHelperThatIgnoresSigterm() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  let pidFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("mcp-probe-pid-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: pidFile) }

  // `exec` replaces the shell with `sleep` in the same process (matching the
  // single-process shape of the real helper) instead of forking it as a
  // child; SIG_IGN dispositions set via `trap` survive `exec` per POSIX, so
  // `sleep` keeps ignoring SIGTERM. Forking `sleep` as a child instead would
  // leave it running as an orphan after the shell is SIGKILLed, holding the
  // stdout/stderr pipes open until its own sleep elapses. The 2-minute sleep
  // is intentionally far longer than this test ever waits: it only ever
  // completes if the fix regresses and the probe hangs on the real exit.
  try Data(
    """
    #!/bin/sh
    trap '' TERM
    echo $$ > \(pidFile.path)
    exec sleep 120
    """.utf8
  ).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

  let clock = ContinuousClock()
  let start = clock.now
  let status = await MCPHelperProbe.probe(
    bundleURL: bundle,
    timeoutSeconds: 1,
    terminationGraceSeconds: 1
  )
  let elapsed = start.duration(to: clock.now)

  #expect(status == .runtimeFailed)
  // A generous bound (versus the ~2s this takes when uncontended) that stays
  // far below the helper's 2-minute sleep even under heavy machine load, so
  // this only fails if the fix regresses and the probe hangs on the real
  // process exit instead of the timeout/SIGKILL escalation resolving it.
  #expect(elapsed < .seconds(60))

  for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidFile.path) {
    try await Task.sleep(for: .milliseconds(50))
  }
  let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  let pid = try #require(pid_t(pidText))
  // SIGTERM was ignored, so a live process here means SIGKILL escalation
  // never ran. ESRCH (kill returns -1) confirms it is actually gone.
  #expect(kill(pid, 0) == -1)
}

/// M13: the probe seeds the child helper's environment from the inherited
/// (parent) environment, so a `LORVEX_APPLE_DB_PATH` the parent carries (a dev
/// shell or Xcode scheme) would otherwise leak into the child and point it at a
/// dev database rather than the shipping managed App Group store. The probe
/// strips it from the inherited base before overlaying the config env; the fake
/// helper here dumps what it received so the strip is observable.
@Test
func mcpHelperProbeStripsInheritedDatabaseSelectionFromChildEnv() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let outFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("mcp-probe-env-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: outFile) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  try Data(
    """
    #!/bin/sh
    printf 'DBPATH=%s\\n' "${LORVEX_APPLE_DB_PATH-UNSET}" > "$LORVEX_PROBE_OUT"
    exit 0
    """.utf8
  ).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

  // A parent that carries a dev DB override, with a client config that omits it
  // (the shipping managed-store config). PATH/HOME survive from the real
  // inherited env so the helper's shell still runs.
  let inherited = ProcessInfo.processInfo.environment.merging([
    "LORVEX_APPLE_DB_PATH": "/parent/leaked.sqlite",
  ]) { _, injected in injected }

  let status = await MCPHelperProbe.probe(
    bundleURL: bundle,
    environment: ["LORVEX_PROBE_OUT": outFile.path],
    inheritedEnvironment: inherited
  )

  #expect(status == .ready)
  let dumped = try String(contentsOf: outFile, encoding: .utf8)
  #expect(dumped.contains("DBPATH=UNSET"))
}

/// The strip only drops what the client config does NOT set: a config env that
/// carries an explicit `LORVEX_APPLE_DB_PATH` still reaches the child (the
/// overlay wins over the stripped base), so an unsandboxed dev override is
/// honored.
@Test
func mcpHelperProbeConfigDatabaseSelectionOverridesInherited() async throws {
  let bundle = try makeSyntheticBundle()
  defer { try? FileManager.default.removeItem(at: bundle) }

  let outFile = FileManager.default.temporaryDirectory
    .appendingPathComponent("mcp-probe-env-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: outFile) }

  let helper = MCPHelperProbe.helperURL(bundleURL: bundle)
  try Data(
    """
    #!/bin/sh
    printf 'DBPATH=%s\\n' "${LORVEX_APPLE_DB_PATH-UNSET}" > "$LORVEX_PROBE_OUT"
    exit 0
    """.utf8
  ).write(to: helper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

  let inherited = ProcessInfo.processInfo.environment.merging([
    "LORVEX_APPLE_DB_PATH": "/parent/leaked.sqlite",
  ]) { _, injected in injected }

  let status = await MCPHelperProbe.probe(
    bundleURL: bundle,
    environment: [
      "LORVEX_PROBE_OUT": outFile.path,
      "LORVEX_APPLE_DB_PATH": "/config/chosen.sqlite",
    ],
    inheritedEnvironment: inherited
  )

  #expect(status == .ready)
  let dumped = try String(contentsOf: outFile, encoding: .utf8)
  #expect(dumped.contains("DBPATH=/config/chosen.sqlite"))
}
