import Foundation
import LorvexCore

/// Access to the Localizable.xcstrings catalog bundled with LorvexWidgetKitSupport.
///
/// LorvexWidgetKitSupport is a framework target, so user-facing strings baked
/// into the render model / timeline status here must route through
/// `WidgetSupportL10n` to reach the module catalog rather than `Bundle.main`.
/// These strings render in the widget views beside `WidgetL10n` (LorvexWidgetViews)
/// strings, so both must carry the same shipped locale set. `public` so the
/// widget extension (which depends on this module and has no catalog of its own)
/// can localize its gallery display names + fallback views through the same
/// catalog.
public enum WidgetSupportL10n {
    /// Anchor for `Bundle(for:)` in the native Xcode framework build.
    private final class BundleAnchor {}

    /// The bundle containing `Localizable.xcstrings`. Installed apps resolve it
    /// from `Contents/Resources`; SwiftPM's generated `.module` accessor is only
    /// a development fallback.
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
            return LorvexResourceBundleResolver.bundle(
                named: "LorvexApple_LorvexWidgetKitSupport.bundle",
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
