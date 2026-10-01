import Foundation
import LorvexCore

/// Provides access to the Localizable.xcstrings catalog bundled with LorvexApple.
///
/// All `LocalizedStringResource` values in LorvexApple should use
/// `LorvexL10n.bundle` so lookups reach the catalog rather than the host app's
/// main bundle.
///
/// In Xcode builds driven by XcodeGen, the resources are embedded in the app
/// bundle and `Bundle.main` resolves correctly; the module bundle is used here
/// for full SwiftPM compatibility.
enum LorvexL10n {
    /// The bundle containing `Localizable.xcstrings` for LorvexApple.
    ///
    /// Exposed as `public` so the test target can load it and verify the
    /// compiled string tables it ships.
    public static let bundle: Bundle = LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexApple.bundle",
        swiftPMBundle: Bundle.module)
}

/// Compose an already-localized title and its value/count into a single
/// accessibility label through a localizable `"%1$@, %2$@"` format, so the
/// separator and ordering follow the resolved locale instead of a hardcoded
/// `", "`. VoiceOver reads the result, so it is user-facing text.
func lorvexPairLabel(_ title: String, _ value: String) -> String {
    String(
        format: String(
            localized: "a11y.pair.label",
            defaultValue: "%1$@, %2$@",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
        title, value)
}
