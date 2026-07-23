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

    /// The locale selected for this module's localized resources. App-specific
    /// language selection does not necessarily change `Locale.current`, so
    /// user-facing formatters must follow the bundle's preferred localization
    /// rather than the device-wide locale.
    static let locale = resolvedLocale(
        preferredLocalizations: bundle.preferredLocalizations,
        fallback: .current)

    static func resolvedLocale(
        preferredLocalizations: [String],
        fallback: Locale
    ) -> Locale {
        guard let identifier = preferredLocalizations.first, identifier != "Base" else {
            return fallback
        }
        return Locale(identifier: identifier)
    }

    /// The source catalog URL used by structural completeness tests.
    static var catalogURL: URL? {
        bundle.url(forResource: "Localizable", withExtension: "xcstrings")
    }
}
