import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexCarPlay.
///
/// CarPlay strings must stay short, glanceable, and driver-safe, but they still
/// need the same module-scoped localization path as the other Apple surfaces.
public enum CarPlayL10n {
  /// Anchor for `Bundle(for:)` in native Xcode framework builds.
  private final class BundleAnchor {}

  /// The bundle containing `Localizable.xcstrings` for LorvexCarPlay.
  public static let bundle: Bundle = {
    #if SWIFT_PACKAGE
      return LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexCarPlay.bundle",
        bundleFor: BundleAnchor.self,
        swiftPMBundle: Bundle.module)
    #else
      return Bundle(for: BundleAnchor.self)
    #endif
  }()

  /// Exposed for catalog completeness tests across every shipped language.
  public static var catalogURL: URL? {
    bundle.url(forResource: "Localizable", withExtension: "xcstrings")
  }
}
