import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexWatch.
///
/// LorvexWatch is a framework target, so every native localized lookup must
/// pass `WatchL10n.bundle` explicitly instead of resolving against the host
/// app's `Bundle.main`.
enum WatchL10n {
    /// Anchor for `Bundle(for:)` in the native Xcode framework build.
    private final class BundleAnchor {}

    /// The bundle containing `Localizable.xcstrings` for LorvexWatch. Installed
    /// apps resolve it from `Contents/Resources`; SwiftPM's generated `.module`
    /// accessor is only a development fallback.
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
            return LorvexResourceBundleResolver.bundle(
                named: "LorvexApple_LorvexWatch.bundle",
                bundleFor: BundleAnchor.self,
                swiftPMBundle: Bundle.module)
        #else
            return Bundle(for: BundleAnchor.self)
        #endif
    }()

    /// The URL of the Localizable.xcstrings file, exposed for catalog
    /// completeness tests across every shipped language.
    static var catalogURL: URL? {
        bundle.url(forResource: "Localizable", withExtension: "xcstrings")
    }
}
