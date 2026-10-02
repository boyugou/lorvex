import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexMobile.
///
/// LorvexMobile is a framework target, so bare `Text("…")` / `Label("…")` /
/// `.navigationTitle("…")` literals resolve against `Bundle.main` (the host
/// app), not this framework's catalog. Every native localized lookup must pass
/// `MobileL10n.bundle` explicitly so it reaches the module catalog.
enum MobileL10n {
    /// Anchor for `Bundle(for:)` in the native Xcode framework build.
    private final class BundleAnchor {}

    /// The bundle containing `Localizable.xcstrings` for LorvexMobile. Installed
    /// apps resolve it from `Contents/Resources`; SwiftPM's generated `.module`
    /// accessor is only a development fallback.
    ///
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
            return LorvexResourceBundleResolver.bundle(
                named: "LorvexApple_LorvexMobile.bundle",
                bundleFor: BundleAnchor.self,
                swiftPMBundle: Bundle.module)
        #else
            return Bundle(for: BundleAnchor.self)
        #endif
    }()
}
