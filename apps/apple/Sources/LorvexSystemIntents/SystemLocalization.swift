import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexSystemIntents.
///
/// App Intents can be surfaced outside the app in Shortcuts, Siri, Spotlight,
/// and system configuration UI. Route every user-visible system intent string
/// through this helper so those surfaces use the framework catalog instead of
/// resolving literals from the host bundle.
public enum SystemL10n {
  private final class BundleAnchor {}

  public static let bundle: Bundle = {
    #if SWIFT_PACKAGE
      return LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexSystemIntents.bundle",
        bundleFor: BundleAnchor.self,
        swiftPMBundle: Bundle.module)
    #else
      return Bundle(for: BundleAnchor.self)
    #endif
  }()

  public static var catalogURL: URL? {
    bundle.url(forResource: "Localizable", withExtension: "xcstrings")
  }
}
