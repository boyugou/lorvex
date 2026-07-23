import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexWidgetViews.
///
/// LorvexWidgetViews is a framework target, so bare `Text("…")` / `Label("…")`
/// literals resolve against `Bundle.main` (the host app), not this framework's
/// catalog. Every localized widget string must pass `WidgetL10n.bundle`
/// explicitly so the native String-Catalog lookup reaches this module.
public enum WidgetL10n {
    /// Anchor for `Bundle(for:)` in the native Xcode framework build.
    private final class BundleAnchor {}

    /// The bundle containing `Localizable.xcstrings` for LorvexWidgetViews.
    /// Installed apps resolve it from `Contents/Resources`; SwiftPM's
    /// generated `.module` accessor is only a development fallback. `public` so
    /// LorvexWidgetExtension — which ships no catalog and looks up its
    /// `widget.config.*` / `widget.entity.*` metadata here — can resolve this
    /// module's own bundle instead of guessing at its on-disk location.
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
            return LorvexResourceBundleResolver.bundle(
                named: "LorvexApple_LorvexWidgetViews.bundle",
                bundleFor: BundleAnchor.self,
                swiftPMBundle: Bundle.module)
        #else
            return Bundle(for: BundleAnchor.self)
        #endif
    }()
    /// The URL of the Localizable.xcstrings file, exposed for catalog
    /// completeness tests across every shipped language.
    public static var catalogURL: URL? {
        bundle.url(forResource: "Localizable", withExtension: "xcstrings")
    }
}
