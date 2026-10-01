import Foundation

/// Access to the Localizable.xcstrings catalog bundled with LorvexCore.
///
/// It holds the few words every surface shows identically because they name
/// shared data rather than a surface's own controls, such as the seeded Inbox
/// list's name (``LorvexListNaming``). LorvexCore is linked by every app
/// surface, so one translation serves macOS, iOS, Shortcuts, and widgets.
enum CoreL10n {
  /// Anchor for `Bundle(for:)` in native Xcode framework builds.
  private final class BundleAnchor {}

  /// The bundle containing `Localizable.xcstrings` for LorvexCore.
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
      return LorvexResourceBundleResolver.bundle(
        named: "LorvexApple_LorvexCore.bundle",
        bundleFor: BundleAnchor.self,
        swiftPMBundle: Bundle.module)
    #else
      return Bundle(for: BundleAnchor.self)
    #endif
  }()
}
