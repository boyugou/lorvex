import Foundation
import LorvexCore

/// Outcome of probing the bundled MCP helper that an external assistant launches
/// over stdio. Only covers the part of MCP connectivity Lorvex itself owns —
/// whether the helper binary survived install and can run. The client-side
/// wiring (the command/args entry in the user's own assistant config) lives
/// outside the app and can't be observed from here.
enum MCPHelperProbeStatus: Equatable, Sendable {
  case ready
  case helperMissing
  case helperNotExecutable
  case runtimeFailed
}

/// Probes the bundled `LorvexMCPHost` helper so the MCP settings panel can report
/// a real status instead of an unconditional "ready". The helper ships as a
/// minimal bundled app at `Contents/Helpers/<host>.app` beside the app (see
/// `script/verify_all.sh`) rather than a bare Mach-O, so the App Sandbox can
/// initialize a container for it; external assistants launch the inner
/// executable at `Contents/Helpers/<host>.app/Contents/MacOS/<host>` directly
/// by path. A broken or quarantined install can leave that inner binary
/// missing or non-executable, which is exactly the failure a user comes to
/// this panel to diagnose.
enum MCPHelperProbe {
  /// The bundled helper's inner executable an external assistant launches over
  /// stdio.
  static func helperURL(bundleURL: URL = Bundle.main.bundleURL) -> URL {
    bundleURL.appendingPathComponent(
      "Contents/Helpers/\(LorvexProductMetadata.mcpHostProduct).app/Contents/MacOS/\(LorvexProductMetadata.mcpHostProduct)"
    )
  }

  /// Verifies the bundled helper is present, executable, and can complete its
  /// production self-check. `bundleURL` and `fileManager` are injectable so the
  /// check can be exercised against a synthetic bundle layout in tests.
  /// `environment` is the client-config env overlaid onto the inherited base;
  /// `inheritedEnvironment` is that base (the parent process env by default,
  /// injectable in tests). `terminationGraceSeconds` bounds how long a helper
  /// that ignores the initial SIGTERM (sent once `timeoutSeconds` elapses
  /// without exit) is given before it is force-killed with SIGKILL.
  static func probe(
    bundleURL: URL = Bundle.main.bundleURL,
    fileManager: FileManager = .default,
    environment: [String: String] = [:],
    inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    timeoutSeconds: TimeInterval = 5,
    terminationGraceSeconds: TimeInterval = 2
  ) async -> MCPHelperProbeStatus {
    let helper = helperURL(bundleURL: bundleURL)
    let path = helper.path
    guard fileManager.fileExists(atPath: path) else { return .helperMissing }
    guard fileManager.isExecutableFile(atPath: path) else { return .helperNotExecutable }
    guard
      await runRuntimeProbe(
        helperURL: helper,
        environment: environment,
        inheritedEnvironment: inheritedEnvironment,
        timeoutSeconds: timeoutSeconds,
        terminationGraceSeconds: terminationGraceSeconds
      )
    else {
      return .runtimeFailed
    }
    return .ready
  }

  private static func runRuntimeProbe(
    helperURL: URL,
    environment: [String: String],
    inheritedEnvironment: [String: String],
    timeoutSeconds: TimeInterval,
    terminationGraceSeconds: TimeInterval
  ) async -> Bool {
    let process = Process()
    process.executableURL = helperURL
    var mergedEnvironment = inheritedEnvironment
    // Strip any `LORVEX_APPLE_DB_PATH` inherited from the parent (a dev shell or
    // Xcode scheme) BEFORE overlaying the config env, so the probe validates the
    // shipping managed App Group store the pasted client config actually uses,
    // rather than a leaked dev override. PATH/HOME/sandbox-container vars the
    // helper needs are kept; the config env overlaid below still sets these when
    // it means to.
    mergedEnvironment["LORVEX_APPLE_DB_PATH"] = nil
    for (key, value) in environment { mergedEnvironment[key] = value }
    mergedEnvironment["LORVEX_MCP_PROBE"] = "1"
    process.environment = mergedEnvironment
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error

    do {
      try process.run()
    } catch {
      return false
    }

    async let drainOutput: Data = Task.detached {
      output.fileHandleForReading.readDataToEndOfFile()
    }.value
    async let drainError: Data = Task.detached {
      error.fileHandleForReading.readDataToEndOfFile()
    }.value

    // Race the helper's exit against the timeout. `waitForExit` polls rather
    // than blocking on `Process.terminationHandler` so it is genuinely
    // cancellable: `withTaskGroup` implicitly awaits every child it spawned
    // before returning, even after `cancelAll()`, so a losing child that
    // ignores cancellation (a checked continuation nothing ever resumes)
    // would hang this whole function on a helper that never exits — exactly
    // the bug this replaces.
    let exitedZero = await withTaskGroup(of: Bool.self) { group in
      group.addTask { await waitForExit(process) }
      group.addTask {
        try? await Task.sleep(for: .seconds(timeoutSeconds))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }

    if !exitedZero, process.isRunning {
      await terminateWithEscalation(process, graceSeconds: terminationGraceSeconds)
    }

    _ = await (drainOutput, drainError)
    return exitedZero
  }

  /// Polls `process` until it exits, checking cooperative cancellation between
  /// polls. Used instead of `Process.terminationHandler` (which Swift's
  /// cancellation model cannot interrupt) so that when this loses the race in
  /// `runRuntimeProbe`'s task group, `cancelAll()` unblocks it within one poll
  /// interval instead of leaving it — and the task group awaiting it — stuck
  /// until the helper actually exits.
  private static func waitForExit(
    _ process: Process,
    pollInterval: Duration = .milliseconds(20)
  ) async -> Bool {
    while process.isRunning {
      if Task.isCancelled { return false }
      try? await Task.sleep(for: pollInterval)
    }
    return process.terminationStatus == 0
  }

  /// Escalates a hung helper from a polite SIGTERM to an unignorable SIGKILL
  /// after `graceSeconds`, so a probe timeout never leaves an orphaned helper
  /// process running.
  private static func terminateWithEscalation(
    _ process: Process,
    graceSeconds: TimeInterval
  ) async {
    guard process.isRunning else { return }
    process.terminate()
    try? await Task.sleep(for: .seconds(graceSeconds))
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
  }
}
