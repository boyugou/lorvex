import Foundation

/// Access to the Localizable.xcstrings catalog bundled with LorvexCore.
///
/// It holds the words every surface shows identically because they name shared
/// data rather than a surface's own controls: the seeded Inbox list's name
/// (``LorvexListNaming``), relative day phrases, habit streaks, how a
/// recurrence rule reads (its frequency, interval, anchor, weekdays, and
/// summary), a task's status and priority names, the facts VoiceOver reads for
/// a task, the words a capture line previews (``LorvexCapturePreview``), the
/// names of the data categories an export or import covers
/// (``LorvexDataExportCategory/localizedDisplayName``) and of their groups,
/// and every line of the import summary (``ImportSummaryLine``).
/// LorvexCore is linked by every app surface, so one translation serves macOS,
/// iOS, Shortcuts, and widgets.
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
