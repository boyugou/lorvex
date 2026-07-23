import Foundation

/// Installed-app-aware access to the LorvexSync SwiftPM resource bundle.
///
/// SwiftPM's generated Bundle.module accessor is correct for source builds and
/// tests, but an installed executable may look beside the app root instead of
/// under Contents/Resources. Manual macOS packaging stages this bundle in the
/// outer app and the nested MCP helper, so production resolution checks those
/// sealed app/extension locations before using Bundle.module as a development
/// fallback.
enum SyncPayloadContractResources {
  private static let bundleName = "LorvexAppleCore_LorvexSync.bundle"
  private final class BundleAnchor: NSObject {}

  private static let resolvedBundle: Bundle? = {
    let main = Bundle.main
    let anchor = Bundle(for: BundleAnchor.self)
    var candidates: [URL] = []

    if let resourceURL = main.resourceURL {
      candidates.append(resourceURL.appendingPathComponent(bundleName))
    }
    candidates.append(
      main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName)"))
    candidates.append(main.bundleURL.appendingPathComponent(bundleName))
    if let containingApp = containingAppURL(for: main.bundleURL) {
      candidates.append(
        containingApp.appendingPathComponent("Contents/Resources/\(bundleName)"))
    }

    if let resourceURL = anchor.resourceURL {
      candidates.append(resourceURL.appendingPathComponent(bundleName))
    }
    candidates.append(anchor.bundleURL.appendingPathComponent(bundleName))

    for candidate in candidates {
      if let bundle = Bundle(url: candidate) {
        return bundle
      }
    }

    // Never invoke Bundle.module inside an installed .app or .appex after the
    // valid sealed-resource candidates failed: SwiftPM's generated accessor may
    // fatalError for either layout. Packaging verification reports the missing
    // bundle; runtime returns a typed infrastructure failure.
    if isInstalledContainer(main.bundleURL) {
      return nil
    }
    return Bundle.module
  }()

  private static func isInstalledContainer(_ bundleURL: URL) -> Bool {
    switch bundleURL.pathExtension.lowercased() {
    case "app", "appex": return true
    default: return false
    }
  }

  private static func containingAppURL(for bundleURL: URL) -> URL? {
    var candidate = bundleURL.deletingLastPathComponent()
    while candidate.path != "/" {
      if candidate.pathExtension.lowercased() == "app" { return candidate }
      let parent = candidate.deletingLastPathComponent()
      if parent == candidate { break }
      candidate = parent
    }
    return nil
  }

  static func data(version: UInt32) throws -> Data {
    let baseName = String(format: "%03u", version)
    guard let bundle = resolvedBundle,
      let url = bundle.url(
        forResource: baseName, withExtension: "json", subdirectory: "SyncPayloadContracts")
    else {
      throw SyncPayloadContractError.missingResource(version: version)
    }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw SyncPayloadContractError.invalidManifest(
        version: version, detail: "resource read failed: \(error)")
    }
  }
}
