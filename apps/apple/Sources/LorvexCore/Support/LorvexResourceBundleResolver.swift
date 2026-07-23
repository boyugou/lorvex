import Foundation

/// Resolves SwiftPM resource bundles from a valid installed macOS app layout.
///
/// SwiftPM's generated `Bundle.module` accessor for executable targets checks
/// `Bundle.main.bundleURL/<Package>_<Target>.bundle`, which is not a valid
/// sealed macOS app resource location. Packaged Lorvex apps and extensions stage
/// resource bundles under their own `Contents/Resources`, so runtime code should
/// resolve sealed process resources first and use `Bundle.module` only as a
/// development fallback.
public enum LorvexResourceBundleResolver {
  public static func bundle(
    named bundleName: String,
    bundleFor anchor: AnyClass? = nil,
    swiftPMBundle: @autoclosure () -> Bundle? = nil
  ) -> Bundle {
    let main = Bundle.main
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

    if let anchor {
      let anchorBundle = Bundle(for: anchor)
      if let resourceURL = anchorBundle.resourceURL {
        candidates.append(resourceURL.appendingPathComponent(bundleName))
      }
      candidates.append(anchorBundle.bundleURL.appendingPathComponent(bundleName))
    }

    for url in candidates {
      if let bundle = Bundle(url: url) {
        return bundle
      }
    }

    // In an installed app or extension, never call SwiftPM's generated
    // Bundle.module fallback: for executable targets it can fatalError while
    // looking beside the sealed container root. Packaging verification is
    // responsible for ensuring the process-local Contents/Resources bundle
    // exists; if it does not, degrade to the host bundle instead of crashing
    // during static initialization.
    if !isInstalledContainer(main.bundleURL), let bundle = swiftPMBundle() {
      return bundle
    }
    if let anchor {
      return Bundle(for: anchor)
    }
    return main
  }

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
}
