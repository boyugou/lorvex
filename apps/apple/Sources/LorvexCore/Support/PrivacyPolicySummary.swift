import Foundation

/// Loads the bundled plain-language privacy summary shipped with the app.
///
/// The summary is a hand-maintained, non-localized reference document (legal
/// content, like the acknowledgments notices) that mirrors the authoritative
/// full privacy policy. It links out to the policy's public lorvex.app URL for
/// the complete text.
public enum PrivacyPolicySummary {
  /// Anchor for `Bundle(for:)` so the resource resolves from the bundle
  /// carrying this module's code.
  private final class ResourceAnchor {}

  /// The public URL for the full, authoritative privacy policy.
  public static let fullPolicyURL = "https://lorvex.app/privacy/"

  private static func resourceBundle() -> Bundle {
    #if SWIFT_PACKAGE
      LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexCore.bundle",
        bundleFor: ResourceAnchor.self,
        swiftPMBundle: Bundle.module)
    #else
      Bundle(for: ResourceAnchor.self)
    #endif
  }

  /// The bundled privacy summary text. Falls back to the in-repo source file
  /// (mirroring the schema/checksums dev fallback) when no packaged resource
  /// bundle is found, and to a short explanatory placeholder — never a crash —
  /// if neither is available.
  public static var text: String {
    let resolved = resourceBundle()
    for bundle in [resolved, Bundle(for: ResourceAnchor.self), Bundle.main] {
      if let url = bundle.url(forResource: "PRIVACY_SUMMARY", withExtension: "md"),
        let contents = try? String(contentsOf: url, encoding: .utf8)
      {
        return contents
      }
    }
    let devPath = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Support
      .deletingLastPathComponent()  // LorvexCore
      .appendingPathComponent("Resources/PRIVACY_SUMMARY.md")
    if let contents = try? String(contentsOf: devPath, encoding: .utf8) {
      return contents
    }
    return "The privacy summary is unavailable in this build. Read the full policy at \(fullPolicyURL)."
  }
}
